########################################################
# Description : Kickstart for Redhat Linux 7.9
# Create DATE : 2022.09.15
# Last Update DATE : 2026.02.06 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2024
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

### Create Partition ============================================================================= #
%pre --log=/tmp/ks-pre.log
#!/bin/bash
DISK="sda"
BOOTSIZE=2048      # /boot       2GB
EFISIZE=200        # /boot/efi 200MB
ROOTSIZE=153600    # /         150GB

# Gather size for SWAP
function GatherSizing() {
  MEM_MB=$(grep MemTotal /proc/meminfo | awk '{printf("%d"), $2/1024}')
  # swap (Max 8GB)
  if [ ${MEM_MB} -le 2048 ]
  then
    SWAPSIZE=$((${MEM_MB} * 2))
  else
    SWAPSIZE=8192
  fi
}

# Get disk for install bootloader (Against USB is mounted to /dev/sda)
DISK=$(blkid | grep -Ev 'sr0|loop|mapper|run|vfat|zram0' | awk -F'/|:' '{print $3}' | sed 's/[^a-z]//g' | sort | head -1)
# If $DISK is null set "sda"
if [ -z "$DISK" ]
then
  DISK="sda"
fi

GatherSizing
echo "zerombr" > /tmp/part-include
echo "ignoredisk --only-use=${DISK}" >> /tmp/part-include
echo "clearpart --all --initlabel" >> /tmp/part-include
echo "bootloader --location=mbr --driveorder=${DISK}" >> /tmp/part-include
echo "part /boot --fstype=xfs --size=${BOOTSIZE}" >> /tmp/part-include

# Check EFI mode
if [ -d "/sys/firmware/efi" ]
then
  echo "part /boot/efi --fstype=efi --size=${EFISIZE}" >> /tmp/part-include
fi

echo "part swap --fstype=swap --size=${SWAPSIZE}" >> /tmp/part-include
echo "part / --fstype=xfs --size=${ROOTSIZE}" >> /tmp/part-include

%end


### Tasks after partitioned with nochroot ======================================================== #
%pre-install --log=/mnt/sysimage/root/ks-pre-install.log
# Copy RPM
TARGET="/mnt/sysimage/root"
df -hT
cp -r /run/install/repo/custom/rpm ${TARGET}/
chmod 644 ${TARGET}/rpm/*.rpm
%end


### Install packages ============================================================================= #
%packages --ignoremissing
@^minimal-environment
gcc
krb5-devel
man-pages
man-pages-overrides
net-tools
#ksh
openssl-devel
-postfix
perl
#rpcbind
#sos
sysstat
vim-enhanced
#xinetd
zlib-devel
%end


# Post-Installation ============================================================================= #
%post --log=/root/ks-post.log
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
[local]
name=CentOS-$releasever - Updates
baseurl=file:///mnt/repo
enabled=1
gpgcheck=0
EOF


##### rhsmd off #####
sed -i 's/\/usr/#\/usr/' /etc/cron.daily/rhsmd


##### UseDNS no #####
sed -i 's/\#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config


##### Loopback network #####
echo "MTU=1500" >> /etc/sysconfig/network-scripts/ifcfg-lo


##### Kernel patch #####
RPMDIR="/root/rpm"
rpm -ivh ${RPMDIR}/kernel-3.10.0-1160.108.1.el7.x86_64.rpm
rpm -Uvh ${RPMDIR}/kernel-devel-3.10.0-1160.108.1.el7.x86_64.rpm
rpm -Uvh ${RPMDIR}/kernel-headers-3.10.0-1160.108.1.el7.x86_64.rpm
rpm -Uvh ${RPMDIR}/kernel-tools-3.10.0-1160.108.1.el7.x86_64.rpm
rpm -Uvh ${RPMDIR}/kernel-tools-libs-devel-3.10.0-1160.108.1.el7.x86_64.rpm



# [ Security ]
##### Set Banner File #####
cat << EOF > /etc/motd
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
#cat /etc/issue > /etc/issue.net

sed -i '/^#smtpd_banner/s/^#//g' /etc/postfix/main.cf


##### Delete not using user #####
mkdir /root/backup
cp /etc/passwd /root/backup/passwd.org
userdel lp
userdel shutdown
userdel operator
userdel sync
userdel halt
userdel ftp
groupdel input
echo >> /etc/csh.login
echo 'set autologout=10' >> /etc/csh.login

##### Add "suser" #####
useradd -u 1000 suser
echo 'skt7979' | passwd --stdin suser
echo -e 'suser\tALL=(ALL)\tNOPASSWD:ALL' > /etc/sudoers.d/suser


##### Passwd policy with /etc/login.defs #####
# PASS_MAX_DAYS   70
# PASS_MIN_DAYS   7
# PASS_MIN_LEN    10
sed -i '/^PASS_MAX_DAYS/ {s/[0-9]\{1,\}/70/}' /etc/login.defs
sed -i '/^PASS_MIN_DAYS/ {s/[0-9]\{1,\}/7/}' /etc/login.defs
sed -i '/^PASS_MIN_LEN/  {s/[0-9]\{1,\}/9/}' /etc/login.defs
echo SULOG_FILE /var/log/sulog >> /etc/login.defs


##### FTP configuration #####
ISFTP=$(rpm -q vsftpd | grep -E 'vsftpd-[0-9]')
if [ -n "${ISFTP}" ]
then
	sed -i '/anonymous_enable/ {s/YES/NO/}' /etc/vsftpd/vsftpd.conf
	sed -i 's/#ftpd_banner=Welcome to blah FTP service/ftpd_banner=WARNING:Authorized use only/' /etc/vsftpd/vsftpd.conf
fi


##### Permission #####
touch /etc/hosts.equiv
chmod 000 /etc/hosts.equiv
touch /root/.rhosts
chmod 000 /root/.rhosts
chmod 640 /etc/rsyslog.conf
#chown -R root. /var/log/cups
chown root.wheel /bin/su
chmod 4750 /bin/su
chmod 755 /usr/bin/newgrp
chmod 755 /sbin/unix_chkpwd


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
sed -i -r '/pam_tally2.so/s/deny=[0-9]+/deny=5/' ${SYTEM_AUTH}

# password-auth-ac
PASSWD_AUTH="/etc/pam.d/password-auth-ac"
sed -i '4 a\auth        required      pam_tally2.so onerr=fail deny=10 unlock_time=3600 magic_root' ${PASSWD_AUTH}
sed -i '10 a\account     required      pam_tally2.so magic_root' ${PASSWD_AUTH}
sed -i '/pam_faildelay/ {s/^/#/}' ${PASSWD_AUTH}
sed -i -r '/pam_tally2.so/s/deny=[0-9]+/deny=5/' ${PASSWD_AUTH}

# su
sed -i '/pam_wheel.so use_uid/s/^#//' /etc/pam.d/su


##### kdump settings #####
sed -i '/^core_collector/ {s/-l/-c/}' /etc/kdump.conf


##### Added 2026.02.06 for SmartGuard
sed -i '/minlen/s/^# //' /etc/security/pwquality.conf
sed -i '/dcredit/s/# dcredit = [0-9]/dcredit = -1/' /etc/security/pwquality.conf
sed -i '/ucredit/s/# ucredit = [0-9]/ucredit = -1/' /etc/security/pwquality.conf
sed -i '/lcredit/s/# lcredit = [0-9]/lcredit = -1/' /etc/security/pwquality.conf
sed -i '/ocredit/s/# ocredit = [0-9]/ocredit = -1/' /etc/security/pwquality.conf


##### /etc/profile #####
sed -i '/umask/s/002/022/g' /etc/profile
sed -i '/umask/s/002/022/g' /etc/bashrc

cat << EOF >> /etc/profile

# Added for SKT
export HISTSIZE=5000
export HISTTIMEFORMAT='%F %T '
export TMOUT=300
set -o vi
alias vi='vim'
EOF


##### /etc/logrotate.conf #####
sed -i 's/^weekly/monthly/;s/rotate\ 4/rotate\ 12/' /etc/logrotate.conf
sed -i 's/0664/0600/'                               /etc/logrotate.conf


##### Disable service
systemctl disable rpcbind
systemctl disable postfix

exit
%end
