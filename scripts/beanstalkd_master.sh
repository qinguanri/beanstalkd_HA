#!/bin/bash

LOGFILE="/var/log/keepalived-beanstalkd.log"

echo "=====================" >> $LOGFILE
date >> $LOGFILE
echo "Being master..." >> $LOGFILE
echo "service beanstalkd  restart" >> $LOGFILE

cmd=`service beanstalkd restart`

echo "$cmd" >> $LOGFILE
