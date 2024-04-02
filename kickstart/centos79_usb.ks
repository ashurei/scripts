#!/bin/bash
########################################################
# Description : kickstart config file
# Create DATE : 2021.03.05
# Last Update DATE : 2021.03.19 by ashurei
# Copyright (c) Technical Solution, 2020
########################################################

install
text
#cdrom
#key --skip
lang en_US.UTF-8
keyboard us
network --device link --bootproto dhcp --onboot off --noipv6 --hostname custom
rootpw imsi00
firewall --disabled
selinux --disabled
authconfig --enableshadow --passalgo=sha512
timezone Asia/Seoul
poweroff
%include /tmp/part-include

%pre --log=/mnt/sysimage/root/ks-pre.log
#!/bin/bash
BOOTSIZE=1024		# /boot 2G
ROOTSIZE=20480		# /     20G
USRSIZE=20480		# /usr  20G
VARSIZE=36864		# /var  36G
HOMESIZE=20480		# /home 20G

GatherSizing() {
	MEM_MB=$(grep MemTotal /proc/meminfo | awk '{printf("%d"), $2/1024}')
	
	# /var/crash (Max 64GB)
	if [ ${MEM_MB} -ge 66000 ]
	then
		CRASHSIZE=65536
	else
		CRASHSIZE=$MEM_MB
	fi

	# swap (Max 8GB)
	if [ ${MEM_MB} -le 2048 ]
	then
		SWAPSIZE=$((${MEM_MB} * 2))
	else
		SWAPSIZE=8192
	fi
}
Clearing () {
    echo "zerombr" >> /tmp/part-include
    echo "ignoredisk --only-use sda" >> /tmp/part-include
    echo "clearpart --initlabel --all" >> /tmp/part-include
}
PartitioningEfiBoot () {
    echo "bootloader --location partition --driveorder sda" >> /tmp/part-include
    echo "part /boot --fstype xfs --size $BOOTSIZE --asprimary" >> /tmp/part-include
    echo "part /boot/efi --fstype vfat --size 256 --asprimary" >> /tmp/part-include
    echo "part swap --fstype swap --size $SWAPSIZE" >> /tmp/part-include
}
PartitioningLegacyBoot () {
    echo "bootloader --location mbr --driveorder sda" >> /tmp/part-include
    echo "part /boot --fstype xfs --size $BOOTSIZE --asprimary" >> /tmp/part-include
    echo "part swap --fstype swap --size $SWAPSIZE --asprimary" >> /tmp/part-include
}
PartitioningCommon () {
    echo "part / --fstype xfs --size $ROOTSIZE --asprimary" >> /tmp/part-include
    echo "part /usr --fstype xfs --size $USRSIZE" >> /tmp/part-include
	echo "part /var --fstype xfs --size $VARSIZE" >> /tmp/part-include
    echo "part /var/crash --fstype xfs --size $CRASHSIZE" >> /tmp/part-include
    echo "part /home --fstype xfs --size $HOMESIZE" >> /tmp/part-include
    echo "part pv.253005 --grow --size=200" >> /tmp/part-include
}

GatherSizing;
Clearing;
if [ -d /sys/firmware/efi ]
then
	PartitioningEfiBoot;
	PartitioningCommon;
else
	PartitioningLegacyBoot;
	PartitioningCommon;
fi
%end

%packages --nobase
ethtool
gcc
krb5-devel
ksh
lvm2
man-pages
man-pages-overrides
net-tools
ntp
ntpdate
openssh-clients
openssl-devel
pciutils
perl
rpcbind
sos
sysstat
tcp_wrappers
unzip
vim-enhanced
xinetd
zip
zlib-devel
%end

%post --log=/mnt/sysimage/root/ks-post.log

# Post-Installation ============================================================================= #
#!/bin/bash
##### /etc/security/limits.conf #####
cat << EOF >> /etc/security/limits.conf

# Added for SKT
*		soft	nofile		8192
*		hard	nofile		65535
*		soft	nproc		8192
*		soft	core		20480
EOF


##### /etc/cron.d/sysstat #####
# Change per 10mins to per 1min
sed -i 's/\*\/10/\*\/1/' /etc/cron.d/sysstat


##### Local yum repository #####
mkdir -p /etc/yum.repos.d/org
mv /etc/yum.repos.d/CentOS-* /etc/yum.repos.d/org/
cat << EOF > /etc/yum.repos.d/local.repo
[Server]
name=Server
baseurl=file:///media/
enabled=0
gpgcheck=0
EOF


##### rhsmd off #####
sed -i 's/\/usr/#\/usr/' /etc/cron.daily/rhsmd


##### UseDNS no #####
sed -i 's/\#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config


##### Loopback network #####
echo "MTU=1500" >> /etc/sysconfig/network-scripts/ifcfg-lo


##### Install additional rpm
mount LABEL=CENT79 /media
rpm -ivh /media/kernel-3.10.0-1160.15.2.el7.x86_64.rpm
rpm -Uvh /media/kernel-devel-3.10.0-1160.15.2.el7.x86_64.rpm
rpm -Uvh /media/kernel-headers-3.10.0-1160.15.2.el7.x86_64.rpm
rpm -Uvh /media/kernel-tools-3.10.0-1160.15.2.el7.x86_64.rpm kernel-tools-libs-3.10.0-1160.15.2.el7.x86_64.rpm
rpm -ivh /media/ssacli-4.21-7.0.x86_64.rpm
umount /media


##### cmdline #####
# numa=off, transparent_hugepage=never, ipv6_disable=1 (intel_idle.max_cstate=0, processor.max_cstate=1, intel_pstate=disable)
sed -i '/GRUB_CMDLINE_LINUX/ {s/\"$/ numa=off transparent_hugepage=never ipv6.disable=1\"/}' /etc/default/grub


##### postfix for ipv6 disable #####
sed -i '/inet_protocols/ {s/all/IPv4/}' /etc/postfix/main.cf


##### IRQBALANCE_ONESHOT #####
sed -i 's/#IRQBALANCE_ONESHOT=/IRQBALANCE_ONESHOT=yes/' /etc/sysconfig/irqbalance


# Security ====================================================================================== #

##### Set Banner File #####
cat << EOF > /etc/issue
 #####################################################################
 #  This system is for the use of authorized users only.             #
 #  Individuals using this computer system without authority, or in  #
 #  excess of their authority, are subject to having all of their    #
 #  activities on this system monitored and recorded by system       #
 #  personnel.                                                       #
 #                                                                   #
 #  In the course of monitoring individuals improperly using this    #
 #  system, or in the course of system maintenance, the activities   #
 #  of authorized users may also be monitored.                       #
 #                                                                   #
 #  Anyone using this system expressly consents to such monitoring   #
 #  and is advised that if such monitoring reveals possible          #
 #  evidence of criminal activity, system personnel may provide the  #
 #  evidence of such monitoring to law enforcement officials.        #
 #####################################################################
EOF
cat /etc/issue > /etc/issue.net


##### Delete not using user #####
cp /etc/passwd /root/backup/passwd.org
sed -i 's/lp/#lp/'             /etc/passwd
sed -i 's/shutdown/#shutdown/' /etc/passwd
sed -i 's/operator/#operator/' /etc/passwd
sed -i 's/sync/#sync/'         /etc/passwd
sed -i 's/halt/#halt/'         /etc/passwd


##### Add "suser" #####
useradd -u 1000 suser
echo 'skt7979' | passwd --stdin suser
echo -e 'suser\tALL=(ALL)\tNOPASSWD:ALL' > /etc/sudoers.d/suser


##### Passwd policy with /etc/login.defs #####
# PASS_MAX_DAYS   70
# PASS_MIN_DAYS   7
# PASS_MIN_LEN    8
sed -i '/^PASS_MAX_DAYS/ {s/[0-9]\{1,\}/70/}' /etc/login.defs
sed -i '/^PASS_MIN_DAYS/ {s/[0-9]\{1,\}/7/}' /etc/login.defs
sed -i '/^PASS_MIN_LEN/  {s/[0-9]\{1,\}/8/}' /etc/login.defs
echo SULOG_FILE /var/log/sulog >> /etc/login.defs


##### FTP configuration #####
ISFTP=$(rpm -q vsftpd | grep -E 'vsftpd-[0-9]')
if [ "${ISFTP}" -eq 1 ]
then
	sed -i '/anonymous_enable/ {s/YES/NO/}' /etc/vsftpd/vsftpd.conf
	sed -i 's/#ftpd_banner=Welcome to blah FTP service/ftpd_banner=WARNING:Authorized use only/' /etc/vsftpd/vsftpd.conf
	sed -i '/listen_ipv6/ {s/YES/NO/}' /etc/vsftpd/vsftpd.conf
fi


##### Permission #####
touch /etc/hosts.equiv
chmod 000 /etc/hosts.equiv
touch /root/.rhosts
chmod 000 /root/.rhosts
chmod 640 /etc/rsyslog.conf
chown -R root. /var/log/cups
chown root.wheel /bin/su
chmod 4750 /bin/su


##### SSH root access configuration #####
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i '/PermitEmptyPasswords/ {s/^#//}'             /etc/ssh/sshd_config
#echo "AllowGroups wheel" >> /etc/ssh/sshd_config


##### pam_tally #####
# system-auth-ac
SYTEM_AUTH="/etc/pam.d/system-auth-ac"
sed -i '4 a\auth        required      pam_tally2.so onerr=fail deny=10 unlock_time=3600 magic_root' ${SYTEM_AUTH}
sed -i '10 a\account     required      pam_tally2.so magic_root' ${SYTEM_AUTH}
sed -i '/pam_faildelay/ {s/^/#/}' ${SYTEM_AUTH}

# password-auth-ac
PASSWD_AUTH="/etc/pam.d/password-auth-ac"
sed -i '4 a\auth        required      pam_tally2.so onerr=fail deny=10 unlock_time=3600 magic_root' ${PASSWD_AUTH}
sed -i '10 a\account     required      pam_tally2.so magic_root' ${PASSWD_AUTH}
sed -i '/pam_faildelay/ {s/^/#/}' ${PASSWD_AUTH}


##### kdump settings #####
sed -i '/^core_collector/ {s/-l/-c/}' /etc/kdump.conf


##### /etc/profile #####
cat << EOF >> /etc/profile

# Added for SKT
umask 0022
export HISTSIZE=5000
export HISTTIMEFORMAT='%F %T '
export TMOUT=300
set -o vi
alias vi='vim'
EOF


##### /etc/logrotate.conf #####
sed -i 's/^weekly/monthly/;s/rotate\ 4/rotate\ 12/;s/rotate\ 1$/rotate\ 12/' /etc/logrotate.conf
sed -i 's/0664/0600/' /etc/logrotate.conf

exit
exit
%end

