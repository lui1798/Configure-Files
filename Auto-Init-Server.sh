#!/bin/bash



link_apps() {
if [ -d /data ];then
​	ln -sf /data /apps
​	chown -R apps.apps /data
else
​	echo "/data not exists"
​	exit 0
fi
}


user_add() {
#新建用户
useradd -u 1001 apps
useradd -u 1002 3kdev
echo $pwd1 | passwd --stdin apps
echo $pwd2 | passwd --stdin 3kdev

#配置sudo
echo "apps ALL=(root) NOPASSWD:  ALL " >>/etc/sudoers

#锁定无用的系统用户
for i in adm lp sync shutdown halt mail uucp operator games gopher dbus rpc vcsa abrt saslauth haldaemon;do
​	passwd -l $i
done

}


set_repo() {
>/etc/yum.repos.d/3k.repo
echo -ne "
[3k-yum]
name=centos6
baseurl=http://$yum_addr/rpms
enable=1
gpgcheck=0
" > /etc/yum.repos.d/3k.repo
}


install_packages() {
yum makecache
yum -y install  gcc make rsync lrzsz libXpm vim bzip2-devel ntp telnet vixie-cron dos2unix unzip cmake libevent2 dmidecode libxml2 libxml2-devel bind-utils wget
yum -y update kernel
# 安装自制的rpm包


disable_fired_walled() {
#关闭防火墙
service iptables stop
service ip6tables stop
/sbin/chkconfig --level 345 iptables off
/sbin/chkconfig --level 345 ip6tables off

#关闭selinux
sed -i '/SELINUX/ s/.*/SELINUX=disabled/' /etc/selinux/config
}



set_env() {
echo "source /apps/sh/app_env.sh" >> /etc/profile
echo "source /apps/sh/web_env.sh" >> /etc/profile
echo "source /apps/sh/java_env.sh" >> /etc/profile
echo "export PS1='[\u@\h \w]\$ '" >> /etc/profile
echo "source /apps/sh/app_env.sh" >> /home/apps/.bash_profile
echo "source /apps/sh/web_env.sh" >> /home/apps/.bash_profile
#source /etc/profile
}

set_ntp() {
echo "*/5 * * * * /usr/sbin/ntpdate ntp4.aliyun.com;hwclock -w 1>/dev/null 2>&1" >> /var/spool/cron/root
service crond restart
service ntpd stop
service postfix stop
/sbin/chkconfig --level 345 ntpd off
/sbin/chkconfig --level 345 postfix off
}

set_ssh(){
#禁止ROOT远程登陆
sed -i -e 's/#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config

#更改SSH默认端口
sed -i -e 's/#Port 22/Port 25635/g' /etc/ssh/sshd_config
#关闭gssapi和dns
sed -i -e 's/GSSAPIAuthentication yes/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
sed -i -e 's/#UseDNS yes/UseDNS no/g' /etc/ssh/sshd_config
#设置PAM
sed -i -e 's/password    requisite     pam_cracklib.so try_first_pass retry=3 type=/password    requisite     pam_cracklib.so  try_first_pass retry=3 difok=4 minlen=8 ucredit=-2 lcredit=-2 dcredit=-2 /g' /etc/pam.d/system-auth
echo "session required        pam_limits.so" >> /etc/pam.d/common-session

#重启SSHD
service sshd restart
}

set_timezone() {
if [ `grep "Asia/Shanghai" /etc/sysconfig/clock|grep -v grep|wc -l` -ne 1 ]
then
echo -ne 'ZONE="Asia/Shanghai"
UTC=false
ARC=false' > /etc/sysconfig/clock
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
fi
}

set_hostname() {
#备份hosts并重新写入
DATE=$(date +%Y%m%d)
mv /etc/hosts /tmp/hosts.$DATE

>/etc/hosts
echo "127.0.0.1 localhost.localdomain localhost" >> /etc/hosts
echo "127.0.0.1 $new_hn" >> /etc/hosts

#重新命名主机名

if [ $(grep ^HOSTNAME /etc/sysconfig/network|wc -l) -eq 1 ];then
  sed -i '/^HOSTNAME/ s/.*/HOSTNAME='$new_hn'/g' /etc/sysconfig/network
else
  echo "HOSTNAME=$new_hn" >> /etc/sysconfig/network
fi
ip=`/sbin/ifconfig |grep "inet addr"|grep -v 127.0.0.1|awk '{print $2}'|awk -F : '{print $2}'`
echo "$ip $new_hn" >> /etc/hosts
echo "$zbx_addr zabbix.3k.com" >> /etc/hosts
}


set_lang() {
if [ `grep "LANG=en" /etc/profile|grep -v grep|wc -l` -ne 1 ]
then
​        #echo "export LANG=en" >> /etc/profile
​        echo "export LANG=en_US.UTF-8" >> /etc/profile
fi
}

set_open_files() {
#备份/etc/security/下的文件
DATE=$(date +%Y%m%d) 
if [ -f /etc/security/limits.d/90-nproc.conf ]
then
​	mv /etc/security/limits.d/90-nproc.conf /tmp/90-nproc.conf.$DATE
fi

if [ -f /etc/security/limits.conf ]
then
​	mv /etc/security/limits.conf /tmp/limits.conf.$DATE
fi
>/etc/security/limits.conf
echo "apps hard nofile 409600" 	>> /etc/security/limits.conf
echo "apps soft nofile 409600" 	>> /etc/security/limits.conf
echo "apps soft nproc 100000" 	>> /etc/security/limits.conf
echo "apps soft nproc 100000" 	>> /etc/security/limits.conf
echo "apps soft stack 10240" 	>> /etc/security/limits.conf
echo "root soft stack 10240"    >> /etc/security/limits.conf
echo "root soft core unlimited" >> /etc/security/limits.conf
echo "root soft nofile 409600" >> /etc/security/limits.conf
echo "root hard nofile 409600" 	>> /etc/security/limits.conf
}


sysctl_config() {
#备份旧的sysctl.conf文件 
DATE=$(date +%Y%m%d)
mv /etc/sysctl.conf /tmp/sysctl.conf.$DATE
#写入新的配置项
>/etc/sysctl.conf
echo -ne "
#limit TIME-WAIT
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3

#该参数设置系统的TIME_WAIT的数量，如果超过默认值则会被立即清除
net.ipv4.tcp_max_tw_buckets  = 20000

#定义了系统中每一个端口最大的监听队列的长度，这是个全局的参数
net.core.somaxconn = 65535

#对于还未获得对方确认的连接请求，可保存在队列中的最大数目
net.ipv4.tcp_max_syn_backlog = 26214

#在每个网络接口接收数据包的速率比内核处理这些包的速率快时，允许送到队列的数据包的最大数目
net.core.netdev_max_backlog = 30000

# 当出现SYN等待队列溢出时,启用cookies来处理,可防范少量SYN攻击,默认为0,表示关闭
net.ipv4.tcp_syncookies = 1

# tcp重用和快速回收需要配合tcp_timestamps使用才有效，但是tcp_timestamps默认是1
net.ipv4.tcp_timestamps = 1

#NAT环境下会导致 客户端发送完tcp syn报文之后，服务器并没有回应ack包，直接drop掉了
#既然必须同时激活tcp_timestamps和tcp_tw_recycle才会触发这种现象， 快速回收对作为客户端和服务端都有效，一定不能开启
net.ipv4.tcp_tw_recycle = 0

# 端口重用只对作为客户端有效
net.ipv4.tcp_tw_reuse = 1 
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_orphan_retries = 3

# TCP memory
# 第一个是这个读缓冲的最小值，第三个是最大值，中间的是默认值。我们可以在程序中修改读缓冲的大小，但是不能超过最小与最大
# 为了使每个socket所使用的内存数最小，我这里设置默认值为4K。
net.ipv4.tcp_rmem = 4096 4096 16777216  

# 写缓冲 单位字节 
net.ipv4.tcp_wmem = 4096 4096 16777216 

# 配置tcp的内存大小，其单位是页，而不是字节。当超过第二个值时，TCP进入pressure模式，此时TCP尝试稳定其内存的使用，
# 当小于第一个值时，就退出pressure模式。当内存占用超过第三个值时，TCP就拒绝分配socket了，查看dmesg，
# 会打出很多的日志“TCP: too many of orphaned sockets”。
net.ipv4.tcp_mem = 786432 2097152 3145728
net.ipv4.tcp_max_orphans = 2000
net.core.rmem_default = 262144  
net.core.wmem_default = 262144  
net.core.rmem_max = 16777216  
net.core.wmem_max = 16777216

#Linux默认的本地端口范围是 32768  61000
net.ipv4.ip_local_port_range = 1024  65535
#max open file
fs.file-max = 1000000
vm.overcommit_memory = 1

# 消息队列内核参数
# 最大消息队列数
kernel.msgmni = 16 

# 同一个消息队列中单个消息的最大大小 bytes
kernel.msgmax = 8192

# 每个消息队列的最大大小 bytes
kernel.msgmnb = 1073741824

# 如果要做防火墙端口映射需要开启这个转发
net.ipv4.ip_forward = 1

" >> /etc/sysctl.conf
}




if [ `whoami` != "root" ]
then
​	echo "You must run by root"
​	exit 1
fi

if [ $# != 5 ]
then
​	echo "$0 hostname apps_passwd 3kdev_passwd rpm_address zbx_addr "
​	exit 1
else
​        pwd1=$2
​        pwd2=$3
​	new_hn=$1
​        yum_addr=$4
​        zbx_addr=$5
​	user_add
​	link_apps
​	set_repo
​	install_packages
​	disable_fired_walled
​	set_env
​	set_ssh
​	set_ntp
​	set_timezone
​	set_hostname
​	set_lang
​	set_open_files
​	sysctl_config
​	chown -R apps.apps /apps
​	chown -R apps.apps /data
​	

	SH_DIR=$(cd `dirname $0`;pwd)
	if [ -f $SH_DIR/$0 ];then
		rm -f $SH_DIR/$0
	fi
	
	echo "All configurations are done,server will be reboot in 60 seconds!"
	/sbin/shutdown -r 1

fi
