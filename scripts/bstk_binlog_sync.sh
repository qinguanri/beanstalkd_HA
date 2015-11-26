#!/bin/bash

# usage: sh bstk_binlog_sync.sh -u SERVER_USER -h SERVER_IP -m MASTER_IP

SERVER_USER=$2         # the account to login rsyc server. Notice, it's not the linux user
MASTER_IP=$4           # the rsync server's ip. "10.17.112.177"

RSYNCD="/usr/bin/rsync"
FROM_DIR="bstk_binlog_dir"
TO_DIR="/var/lib/beanstalkd"

PASSWD_FILE="/etc/rsync_bstk.secret"
LOGFILE="/var/log/keepalived-beanstalkd.log"

echo "=====================" >> $LOGFILE
date >> $LOGFILE
echo "bstk_binlog_sync..." >> $LOGFILE

is_master=`ip a | grep $MASTER_IP | wc -l`
ping_master=`ping $MASTER_IP -c 1 | grep ttl | wc -l`

if [ "$is_master" -eq "1" ]; then :
    echo "I am master" >> $LOGFILE
else
    echo "I am slave" >> $LOGFILE
    if [ "$ping_master" -eq "0" ]; then :
        echo "ping $MASTER_IP failed" >> $LOGFILE
        exit 0
    fi

    echo "backup beanstalkd's binlog..." >> $LOGFILE
    echo "FROM $SERVER_USER@$MASTER_IP::$FROM_DIR  TO $TO_DIR" >> $LOGFILE

    cmd=`$RSYNCD -avzpogP --delete --password-file=$PASSWD_FILE $SERVER_USER@$MASTER_IP::$FROM_DIR $TO_DIR`

    echo "$cmd" >> $LOGFILE
    chown -R beanstalkd:beanstalkd $TO_DIR
fi
