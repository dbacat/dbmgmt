#!/bin/bash
#
# File        sql_get_total_db_size.bash
#
# Goal        run SQL statements on all instances on all servers
#             output collected in a central logfile
#
# Author      michel.stevelinck@smals.be
#
# History     ms 15jul2021  - set working dir for crontab execution
#                           - compute grant total in Tb with 2 decimals
#                           - use , as decimal separator instead of . for excel
#                           - avoid multiple counting by sorting uniquely on database_unique_name
#
cd /home/dbmgmt/dba/ms

all_servers=`grep -Fxv -f ooscope.txt /opt/dbmgmt/agent/serv.lst|grep -v "^#"|sort -u`  #ooscope.txt => list of out of scope servers
#all_servers=ltfeddbs001a.fedict.mgmt.be  #debug purpose

#
# Env
#
export PATH=/opt/rh/rh-python36/root/usr/bin:/usr/lib64/qt-3.3/bin:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/opt/nsr:/opt/nsr/bin:/opt/nsr/sbin:/home/dbmgmt/bin:/opt/pgsql/bin/9.4/bin
#
# SQL script to run on all instances
#
sudo rm -f sqldo.bash
cat<<'EOF' >sqldo.bash
#!/bin/bash
INVERSE='\e[7m'
NOVERSE='\e[27m'

if [ -s /etc/oratab ];then
for mydb in `cat /etc/oratab | grep -v "^+"|grep -v "^-"|grep -v "^#" |awk -F: '{ print $1 }'|awk -F_ '{ print $1 }'`
do
#-------------------------------------------
# find back real instance name from smon
#-------------------------------------------
myinst=`ps -ef |grep smon|grep $mydb| awk '{ print $NF }'|cut -d_ -f3`
#echo "myinst=>$myinst<"
strsize=${#myinst}  #equal 0 if instance is not running

#-------------------------------------------
# find back ORACLE_HOME from /etc/oratab
#-------------------------------------------
myhome=`grep "^${mydb}" /etc/oratab | cut -d: -f2`
#-------------------------------------------
# Export values in environment
#-------------------------------------------
ORACLE_SID=$myinst
export ORACLE_SID
ORACLE_HOME=$myhome
PATH=$ORACLE_HOME/bin:$PATH
export ORACLE_HOME PATH
#-------------------------------------------
# running SQL operations
#-------------------------------------------
if [ $strsize -gt 0 ];then
#printf "${INVERSE}     Running SQL for instance ${myinst}${NOVERSE}\n"
sqlplus -S / as sysdba<<!
set echo off
set feedback off
alter session set NLS_NUMERIC_CHARACTERS = ',.';
set pagesize 0
set linesize 350
select host_name||';'||database_name||';'||dbid||';'||DB_UNIQUE_NAME||';'||database_role||';'||ceil(sum(BYTES)/(1024*1024*1024)) from v\$database, v\$instance, dba_segments
group by host_name,database_name,dbid,DB_UNIQUE_NAME,database_role;
quit
!
fi
#==== end of SQL operations ==============================
done
fi #if /etc/oratab
EOF
sudo chmod 777 sqldo.bash
sudo chown oracle:oinstall sqldo.bash

#
# Main loop on all target hosts
#
cd /home/dbmgmt/dba/ms
echo "host_name;database_name;dbid;DB_UNIQUE_NAME;DBsize_GB">sqlresult.txt
for myserver in $all_servers
do
  timeout 5 scp -p -o StrictHostKeyChecking=no sqldo.bash oracle@${myserver}:/tmp/.
  timeout 60 ssh oracle@${myserver} "/tmp/sqldo.bash" |tee -a sqlresult.txt
  timeout 5 ssh oracle@${myserver} "rm -f /tmp/sqldo.bash"
done
#
# purify result file and generate CSV file
#
sed '/^[[:space:]]*$/d' sqlresult.txt|egrep -v "ERROR|ORA-|select|\*" >sqlresult.csv
#
# Add total Oracle databases size to other csv file
#
ora_tot_gb=`sed -e '1,1d' sqlresult.csv|sort -t ';' -uk4,4 | awk -F ';' '{sum += $6} END { printf "%0.2f", sum/1024}'|sed -e 's/\./,/g'`
today=`date '+%d/%m/%Y'`
printf "\n\nTotal Oracle database size : $ora_tot_gb Tb\n\n"
echo "${today};${ora_tot_gb}" >>Total_Oracle_Data_size_TB.csv
rm -f sqldo.bash
