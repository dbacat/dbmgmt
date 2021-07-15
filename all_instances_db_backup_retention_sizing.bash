#!/bin/bash
#
# File        all_instances_db_backup_retention_sizing.bash
#
# Goal        run SQL statements on all instances on all servers
#             output collected in a central logfile
#
# Author      michel.stevelinck@smals.be
#
#

all_servers=`grep -Fxv -f ooscope.txt /opt/dbmgmt/agent/serv.lst|grep -v "^#"|sort -u`  #ooscope.txt => list of out of scope servers

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
sqlplus -S / as sysdba<<!
--
-- Goal        get db and backup sizing as CSV line to be run on all DBs
--

set serveroutput on
SET FEEDBACK OFF
set linesize 300

DECLARE

my_hostname v\$instance.host_name%type;
my_instance v\$instance.instance_name%type;
my_version  v\$instance.version%type;
my_dbrole   v\$database.database_role%type;
my_db_uniq  v\$database.db_unique_name%type;
my_retention v\$rman_configuration.value%type;
my_tenant    varchar(20);

bu_size_Gb integer;
db_size_Gb integer;
num_retention integer;

begin

------------------------------------------
-- Get general info
------------------------------------------
select i.host_name, i.instance_name, d.db_unique_name, i.version, d.database_role, replace(r.VALUE,'TO RECOVERY WINDOW OF ')
into my_hostname,my_instance,my_db_uniq,my_version,my_dbrole,my_retention
from v\$instance i, v\$database d, V\$RMAN_CONFIGURATION r
where r.value like '%TO RECOVERY WINDOW OF%';

num_retention:=replace(my_retention,' DAYS');
my_tenant:=substr(my_db_uniq,INSTR(my_db_uniq,'_')+1);
------------------------------------------
-- Get backup size
------------------------------------------
select ceil(sum(OUTPUT_BYTES)/(1024*1024*1024)) into bu_size_Gb from V\$RMAN_BACKUP_JOB_DETAILS where START_TIME > sysdate-num_retention;
------------------------------------------
-- Get database size (allocated on disks)
------------------------------------------
select ceil(sum(used.bytes)/(1024*1024*1024)) into db_size_Gb
from (select bytes
from v\$datafile
union all
select bytes
from v\$tempfile
union all
select bytes
from v\$log) used;
------------------------------------------
-- Write CSV format
------------------------------------------
dbms_output.put_line (my_tenant||';'||my_db_uniq||';'||my_hostname||';'||my_instance||';'||my_version||';'||my_dbrole||';'||my_retention||';'||db_size_Gb||';'||bu_size_Gb);
end;
/
quit
!
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
for myserver in $all_servers
do
  #printf "${INVERSE}   $myserver${NOVERSE}\n"
  scp -pq -o StrictHostKeyChecking=no sqldo.bash oracle@${myserver}:/tmp/.
  timeout 60 ssh oracle@${myserver} "/tmp/sqldo.bash 2>/dev/null" |tee -a sqlresult.txt
  timeout 5 ssh oracle@${myserver} "rm -f /tmp/sqldo.bash"
done
#
# purify result file and generate CSV file
#
printf "Cluster name;DB Unique Name;Hostname;Instance;Version;DB Role;\"Backup\nretention\";\"Databse size\"\n\"in GB\";\"Backup size\"\n\"during retention\"\n\"period in GB\"\n" >DB_and_BU_Sizing.csv
grep ";" sqlresult.txt |grep -i "primary"|sort -t ';' -uk2,2|sort -t ';' -k1,1 >>DB_and_BU_Sizing.csv
echo "see attached"|mailx -s "DB_and_BU_Sizing.csv" -r noreply@smals.be -a DB_and_BU_Sizing.csv michel.stevelinck@smals.be
rm -f sqlresult.txt sqldo.bash 2>/dev/null
