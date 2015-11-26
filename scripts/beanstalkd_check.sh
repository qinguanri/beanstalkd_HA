#!/bin/bash 

INACTIVE=`service beanstalkd status | grep 'fail\|inactive' | wc -l`
LOGFILE="/var/log/keepalived-beanstalkd.log"

echo "=====================" >> $LOGFILE
date >> $LOGFILE

if [ "$INACTIVE" -eq "0" ]; then :
    echo "beanstalkd running..." >> $LOGFILE
    exit 0
else
    echo "beanstalkd stoped."    >> $LOGFILE
    exit 1
fi
