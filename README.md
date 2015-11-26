## 1.需求

实现beanstalkd的主备自动切换功能，当beanstalkd的master主机故障或者beanstalkd故障时，能自动切换到备机运行。

## 2.实现思路

采用keepalived双backup模式，并设置不抢占资源。当master挂机，切换为backup；完成修复后，不会抢占为master，避免不必要的切换。
假设两台主机如下，虚IP设成xx.xx.112.50（先确保该ip未被分配）。

* mster host：xx.xx.112.190， ubuntu14.04
* backup host：xx.xx.69.239， ubuntu14.04

安装步骤如下：
1. 安装beanstalkd
2. 安装rsync
3. 安装keepalived
4. 启动


## 3.安装beanstalkd

#### 在ubuntu下使用apt-get安装

```
sudo apt-get install beanstalkd
```

#### 修改beanstalkd默认启动配置项/etc/default/beanstalkd

```
sudo cat /etc/default/beanstalkd
```

```
## Defaults for the beanstalkd init script, /etc/init.d/beanstalkd on
## Debian systems.

BEANSTALKD_LISTEN_ADDR=127.0.0.1
BEANSTALKD_LISTEN_PORT=11300

# You can use BEANSTALKD_EXTRA to pass additional options. See beanstalkd(1)
# for a list of the available options. Uncomment the following line for
# persistent job storage.
BEANSTALKD_EXTRA="-b /var/lib/beanstalkd" 
```

## 4.安装keeplived

```
sudo apt-get install keeplived
```

#### 修改master主机上的/etc/keepalived/keepalived.conf配置文件

```
sudo cat /etc/keepalived/keepalived.conf
```


```
! Configuration File for keepalived

global_defs {
   router_id beanstalkd_router     # all node must same
}

vrrp_script chk_beanstalkd
{
    # exit 0 if beanstalkd is running, exit 1 if beanstalkd is inactive
    script "/etc/keepalived/scripts/beanstalkd_check.sh"

    interval 2 
    timeout 2
    fall 3                         # require 3 failures for failures
}

vrrp_script sync_bstk_binlog
{
    # usage: sh bstk_binlog_sync.sh -u SERVER_USER -h MASTER_IP. Please init before install
    script "/etc/keepalived/scripts/bstk_binlog_sync.sh -u qinguanri -h xx.xx.112.50"
    interval 30                    # backup binlog each 30 seconds
}

vrrp_instance beanstalkd {
    state BACKUP                   # master or backup, please init before install
    interface eth0                 # bind vip on eth0
    virtual_router_id 55           # all node must same
    priority  150                  # 
    advert_int 1                   # send keepalived msg every 1 second
    nopreempt                      # must need

    authentication {               # all node must same
        auth_type PASS
        auth_pass 1111
    }

    virtual_ipaddress {
        xx.xx.112.50               # all node must same. please init before install
    }

    track_script {
        chk_beanstalkd
        sync_bstk_binlog
    }

    notify_master /etc/keepalived/scripts/beanstalkd_master.sh
    notify_backup /etc/keepalived/scripts/beanstalkd_backup.sh
}

```

#### 修改backup主机上的/etc/keepalived/keepalived.conf

```
! Configuration File for keepalived

global_defs {
   router_id beanstalkd_router     # all node must same
}

vrrp_script chk_beanstalkd
{
    # exit 0 if beanstalkd is running, exit 1 if beanstalkd is inactive
    script "/etc/keepalived/scripts/beanstalkd_check.sh"

    interval 2 
    timeout 2
    fall 3                         # require 3 failures for failures
}

vrrp_script sync_bstk_binlog
{
    # usage: sh bstk_binlog_sync.sh -u SERVER_USER -h MASTER_IP. Please init before install
    script "/etc/keepalived/scripts/bstk_binlog_sync.sh -u qinguanri -h xx.xx.112.50"
    interval 30                    # backup binlog each 30 seconds
}

vrrp_instance beanstalkd {
    state BACKUP                   # master or backup, please init before install
    interface eth0                 # bind vip on eth0
    virtual_router_id 55           # all node must same
    priority  140                  # 
    advert_int 1                   # send keepalived msg every 1 second
    #nopreempt                      # must need

    authentication {               # all node must same
        auth_type PASS
        auth_pass 1111
    }

    virtual_ipaddress {
        xx.xx.112.50               # all node must same. please init before install
    }

    track_script {
        chk_beanstalkd
        sync_bstk_binlog
    }

    notify_master /etc/keepalived/scripts/beanstalkd_master.sh
    notify_backup /etc/keepalived/scripts/beanstalkd_backup.sh
}


```

#### 创建shell脚本，放在/etc/keepalived/scripts目录下

> 脚本1：beanstalkd_check.sh

```
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
```

>脚本2：beanstalkd_master.sh

```
#!/bin/bash

LOGFILE="/var/log/keepalived-beanstalkd.log"

echo "=====================" >> $LOGFILE
date >> $LOGFILE
echo "Being master..." >> $LOGFILE
echo "service beanstalkd  restart" >> $LOGFILE

cmd=`service beanstalkd restart`

echo "$cmd" >> $LOGFILE

```

>脚本3:beanstalkd_backup.sh

```
#!/bin/bash

LOGFILE="/var/log/keepalived-beanstalkd.log"

echo "=====================" >> $LOGFILE
date >> $LOGFILE
echo "Being backup..." >> $LOGFILE

```

>脚本4:bstk_binlog_sync.sh

```
#!/bin/bash

# usage: sh bstk_binlog_sync.sh -u SERVER_USER -h SERVER_IP -m MASTER_IP

SERVER_USER=$2         # the account to login rsyc server. Notice, it's not the linux user
MASTER_IP=$4           # the rsync server's ip. "xx.xx.112.177"

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

```

#### keepalived的相关配置文件存储位置如下：

```
qinguanri@qinguanri-VirtualBox:/etc/keepalived$ tree /etc/keepalived/
/etc/keepalived/
├── keepalived.conf
└── scripts
    ├── beanstalkd_backup.sh
    ├── beanstalkd_check.sh
    ├── beanstalkd_master.sh
    └── bstk_binlog_sync.sh

1 directory, 5 files

```

## 安装Rsync

#### 修改/etc/default/rsync文件

```
RSYNC_ENABLE=true
```

#### 配置rsyncd的/etc/rsyncd.conf

```
sudo cat /etc/rsyncd.conf
```

```
log file = /var/log/rsyncd

[bstk_binlog_dir]
comment = public archive
path = /var/lib/beanstalkd
max connections = 10
read only = yes
list = yes
uid = beanstalkd
gid = beanstalkd
auth users = root qinguanri beanstalkd
secrets file = /etc/rsync.secret
strict modes = yes
#hosts allow=127.0.0.1 xx.xx.112.48
ignore errors = yes
ignore nonreadable = yes
transfer logging = no
timeout = 600
refuse options = checksum dry-run
dont compress = *.gz *.tgz *.zip *.z *.rpm *.iso *.bz2 *.tbz

```

#### 修改/etc/rsync.secret

```
sudo cat /etc/rsync.secret
```

```
beanstalkd:passwd
qinguanri:passwd
root:passwd

```

> 修改/etc/rsync.secret文件属性:

```
sudo chown root:root /etc/rsync.secret
sudo chmod 600 /etc/rsync.secret
```

#### 设置防火墙

> 为方便起见，关闭防火墙：

```
service iptables stop
```

#### 启动rsync服务器

```
sudo service rsync restart
```

####  配置rsync客户端,

> 文件/etc/rsync_bstk.secret内容如下

```
passwd
```

> 修改文件权限
```
sudo chmod 600 /etc/rsync_bstk.secret
```

** 注意：如果不修改权限，则会报错ERROR: password file must not be other-accessible**

## 5.启动

#### 1. 启动master主机上的beanstalkd
```
sudo service beanstalkd restart
```

#### 2. 启动master主机上的rsync
```
sudo service rsync restart
```
#### 3. 启动master主机上的keepalived
```
sudo service keepalived restart
```

#### 4. 依次启动backup主机上的beanstalkd、rsync、keepalived

#### 5. 查看启动日志
```
tail -f /var/log/keepalived-beanstalkd.log
```

## 6.自动切换测试

#### 确认beanstalkd、keepalived、rsync已经启动

```
ps -ef | grep beanstalkd
ps -ef | grep keepalived
ps -ef | grep rsync
```

#### 确认master主机已经拥有虚ip

```
qinguanri@qinguanri-VirtualBox:~$ sudo ip a
[sudo] password for qinguanri:
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 08:00:27:03:5b:ca brd ff:ff:ff:ff:ff:ff
    inet xx.xx.112.48/18 brd xx.xx.127.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet xx.xx.112.49/32 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::a00:27ff:fe03:5bca/64 scope link
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default
    link/ether 02:42:6e:62:2c:02 brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 scope global docker0
       valid_lft forever preferred_lft forever
```

#### 切换测试

> 1.停止master主机上的beanstalkd进程，检查backup主机是否获得虚IP。
> 2.或者停止master主机上的keepaived服务，检查backup主机是否获得虚IP。

```
sudo ip a
```

## 进阶
