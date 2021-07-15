# makefile
#
# author : michel.stevelinck@smals.be
#
#
#--------------------------------------------------------------
# Scripts to distribute
#--------------------------------------------------------------
mybinscripts=/home/oracle/dba/ms/toolbox/fra_autowash.bash

myMSscripts=/home/oracle/dba/ms/toolbox/rmanstats.sql\
/home/oracle/dba/ms/toolbox/fra_autowash.bash\
/home/oracle/dba/ms/toolbox/speedtest.bash\
/home/oracle/dba/ms/toolbox/dbsize.bash\
/home/oracle/dba/ms/toolbox/check_oratab.bash\
/home/oracle/dba/ms/Rman/configure_rman.bash

myMSscripts=/home/oracle/dba/ms/toolbox/chk_tracefiles.bash

myMSscripts=/home/oracle/dba/ms/toolbox/fra_autowash.bash

installit=add_crontab.bash

doit=doit.bash
#--------------------------------------------------------------
# List of targets - Manually updated when new server is added
#--------------------------------------------------------------
testsrv=ltfeddbs001a.fedict.mgmt.be                                                                                                  #test deploy server
testsrv2="lpdatdbs100a.dataserv.be lpdatdbs100b.dataserv.be lpdatdbs100c.dataserv.be"
$(eval allservers=$(shell grep -Fxv -f ooscope.txt /opt/dbmgmt/agent/serv.lst|grep -v "^#"|sort -u))                       #all servers
$(eval firstnode=$(shell grep -Fxv -f ooscope.txt /opt/dbmgmt/agent/serv.lst|grep -v "^#" |egrep "*[0-9]a\.*"|sort -u))    #all -a- servers
$(eval persopoint=$(shell grep -v "^#" /opt/dbmgmt/agent/serv.lst|egrep "*fhr*"|sort -u))                                            #Bosa persopoint servers
#--------------------------------------------------------------
# Possible actions - to be use as parameter to "make" command
#--------------------------------------------------------------
local :
        @for myscript in $(myscripts) ;do \
        echo "Distributing script $${myscript} basescript is $${basescript}" ; \
        sudo install -o oracle -g oinstall -m 0700 $${myscript} /data/www/software/oracle/scripts/oracle/shell ; \
        sudo install -o oracle -g oinstall -m 0700 $${myscript} /home/dbmgmt/dba/ms ; \
        sudo install -o oracle -g oinstall -m 0700 $${myscript} /data/www/software/oracle/scripts/oracle/bin ; done

pushbintarget :
        @for myserver in $(mytargets) ;do \
        for myscript in $(mybinscripts) ;do \
        sudo chmod 0754 $${myscript} ; \
        timeout 5 scp -p -o StrictHostKeyChecking=no $${myscript} oracle@$${myserver}:/home/oracle/bin && printf "[ OKAY ] $${myserver}\n" || printf "[ FAIL ] $${myserver}\n" ; done;done

pushMStarget :
        @for myserver in $(allservers) ;do \
        for myscript in $(myMSscripts) ;do \
        sudo chmod 770 $${myscript} ; \
        timeout 5 ssh -o StrictHostKeyChecking=no oracle@$${myserver} "mkdir -p /home/oracle/dba/ms 2>/dev/null" ; \
        timeout 5 scp -p -o StrictHostKeyChecking=no $${myscript} oracle@$${myserver}:/home/oracle/dba/ms/. && printf "[ OKAY ] $${myscript} to $${myserver}\n" || printf "[ FAIL ] $${myscript} to $${myserver}\n" ; done;done

chktarget :
        @cat /dev/null >chktarget.log ; \
        printf "\nChecking targets with dbmgmt user\n\n" ; \
        for myserver in $(mytargets) ;do \
        timeout 5 ssh -o StrictHostKeyChecking=no $${myserver} "date" &>/dev/null && printf "[ OKAY ] $${myserver}\n"|tee -a chktarget.log || printf "[ FAIL ] $${myserver}\n" |tee -a chktarget.log ; done ; \
        ./stats_chktarget.bash ; \
        printf "List of failed servers \n\n";grep FAIL chktarget.log;printf "\n\n"

listpersopoint :
        @for myserver in $(persopoint); do \
        printf "$${myserver}\n" ; done

nolocation :
        @cat /dev/null > servers_without_site.info.txt ; \
        for myserver in $(mytargets) ;do \
        timeout 3 ssh -o StrictHostKeyChecking=no oracle@$${myserver} "ls -l /var/tmp/site.info" &>/dev/null || printf "$${myserver}\n" |tee -a servers_without_site.info.txt ; done ; \
        echo "see attachment" |mailx -s "servers_without_site.info.txt" -r noreply@smals.be -a servers_without_site.info.txt michel.stevelinck@smals.be

chkdown :
        @printf "Checking if all servers are pingable. Displaying errors only. Please wait ...\n\n" ; \
        for myserver in $(mytargets) ;do \
        ping -c1 $${myserver} &>/dev/null || printf "[ FAIL ] $${myserver} is not pingable\n" &>/dev/null ; done

addcrontab :
        @for myserver in $(mytargets) ;do \
        for myscript in $(installit) ;do \
        echo "Updating crontab for server $${myserver}" ; \
        timeout 3 scp -p -o StrictHostKeyChecking=no /home/oracle/dba/ms/toolbox/$${myscript} oracle@$${myserver}:/home/oracle/bin/. && printf "[ OKAY ] copy to $${myserver}\n" || printf "[ FAIL ] copy to $${myserver}\n"; \
        timeout 5 ssh -o StrictHostKeyChecking=no oracle@$${myserver} "/home/oracle/bin/$${myscript} &>/dev/null" && printf "[ OKAY ] exec on $${myserver}\n" || printf "[ FAIL ] exec on $${myserver}\n" ; done;done

runit :
        @for myserver in $(mytargets) ;do \
        timeout 8 ssh -o StrictHostKeyChecking=no $${myserver} "sudo usermod -a -G oinstall dbmgmt" && printf "[ OKAY ] exec on $${myserver}\n" || printf "[ FAIL ] exec on $${myserver}\n" ; done

scprun :
        @echo "hostname;file system;mountpoint;allocated size;used size;pct used" ; \
        for myserver in $(mytargets) ;do \
        for myscript in $(doit) ;do \
        timeout 3 scp -p -o StrictHostKeyChecking=no $${myscript} oracle@$${myserver}:/tmp/. 2>/dev/null ; \
        timeout 5 ssh -o StrictHostKeyChecking=no oracle@$${myserver} "/tmp/doit.bash 2>/dev/null" 2>/dev/null ; done;done

manual :
        @for myserver in $(mytargets) ;do \
        ssh -o StrictHostKeyChecking=no oracle@$${myserver} ; done
