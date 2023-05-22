########################################################
# Description : Kickstart for Rocky Linux 8.7
# Create DATE : 2022.03.11
# Last Update DATE : 2023.05.22 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2023
########################################################

text
#cdrom
url --url=file:///run/install/repo/BaseOS
repo --name="AppStream" --baseurl=file:///run/install/repo/AppStream

keyboard --xlayouts='us'
lang en_US.UTF-8
network --hostname custom
rootpw --plaintext imsi00
firewall --disabled
selinux --disabled
timezone Asia/Seoul
poweroff
%include /tmp/part-include


### Create Partition ============================================================================= #
%pre --logfile=/tmp/ks-pre.log
#!/bin/bash
BOOTSIZE=2048      # /boot       2GB
EFISIZE=200        # /boot/efi 200MB
ROOTSIZE=153600    # /         150GB

GatherSizing() {
  MEM_MB=$(grep MemTotal /proc/meminfo | awk '{printf("%d"), $2/1024}')
  # swap (Max 8GB)
  if [ ${MEM_MB} -le 2048 ]
  then
    SWAPSIZE=$((${MEM_MB} * 2))
  else
    SWAPSIZE=8192
  fi
}

GatherSizing;
echo "zerombr" > /tmp/part-include
echo "ignoredisk --only-use=sda" >> /tmp/part-include
echo "clearpart --all --initlabel" >> /tmp/part-include
echo "bootloader --location=mbr --driveorder=sda" >> /tmp/part-include
echo "part /boot --fstype=xfs --size=$BOOTSIZE" >> /tmp/part-include

if [ -d "/sys/firmware/efi" ]
then
  echo "part /boot/efi --fstype=efi --size=$EFISIZE" >> /tmp/part-include
fi

echo "part swap --fstype=swap --size=$SWAPSIZE" >> /tmp/part-include
echo "part / --fstype=xfs --size=$ROOTSIZE" >> /tmp/part-include

%end


### Tasks after partitioned with nochroot ======================================================== #
%pre-install --logfile=/mnt/sysroot/root/ks-pre-install.log
# Copy RPM
df -hT
#cp -r /run/install/repo/custom/rpm /mnt/sysroot/root/
#chmod 644 /mnt/sysroot/root/rpm/*.rpm
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
pciutils
perl
#rpcbind
#sos
sysstat
tar
vim-enhanced
#xinetd
zlib-devel
%end


### Post-Installation ============================================================================= #
%post --logfile=/root/ks-post.log
#!/bin/bash
##### /etc/security/limits.conf #####
cat << EOF >> /etc/security/limits.conf

# Added for SKT
*               soft    nofile          8192
*               hard    nofile          65535
*               soft    nproc           8192
*               soft    core            20480
EOF


##### Change collection interval of the SAR #####
# Change per 10mins to per 1min
sed -i '/^Description/s/10/1/' /usr/lib/systemd/system/sysstat-collect.timer
sed -i '/^OnCalendar/s/\*\:00\/10/\*\:*\:00/' /usr/lib/systemd/system/sysstat-collect.timer


##### Local yum repository #####
#mkdir -p /etc/yum.repos.d/org
#mv /etc/yum.repos.d/CentOS-* /etc/yum.repos.d/org/
cat << EOF > /etc/yum.repos.d/tb-ossrepo.repo
[local-BaseOS]
name=Server
baseurl=file:///mnt/BaseOS
enabled=0
gpgcheck=0

[local-AppStream]
name=Server
baseurl=file:///mnt/AppStream
enabled=0
gpgcheck=0

[SKT-TB-ROCKY8-baseos]
name=Rocky-BaseOS
baseurl=http://60.30.131.100/repos/rocky/8/BaseOS/x86_64/os
enabled=1
gpgcheck=0

[SKT-TB-ROCKY8-appstream]
name=Rocky-AppStream
baseurl=http://60.30.131.100/repos/rocky/8/AppStream/x86_64/os
enabled=1
gpgcheck=0


##### Kernel patch #####
RPMDIR="/root/rpm"
#rpm -ivh ${RPMDIR}/kernel-core-4.18.0-372.19.1.el8_6.x86_64.rpm ${RPMDIR}/kernel-modules-4.18.0-372.19.1.el8_6.x86_64.rpm ${RPMDIR}/kernel-4.18.0-372.19.1.el8_6.x86_64.rpm
#rpm -ivh ${RPMDIR}/kernel-devel-4.18.0-372.19.1.el8_6.x86_64.rpm
#rpm -Uvh ${RPMDIR}/kernel-headers-4.18.0-372.19.1.el8_6.x86_64.rpm
#rpm -Uvh ${RPMDIR}/kernel-tools-4.18.0-372.19.1.el8_6.x86_64.rpm ${RPMDIR}/kernel-tools-libs-4.18.0-372.19.1.el8_6.x86_64.rpm


# [ Security ]
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
mkdir /root/backup
cp /etc/passwd /root/backup/passwd.org
sed -i 's/lp/#lp/'             /etc/passwd
sed -i 's/shutdown/#shutdown/' /etc/passwd
sed -i 's/operator/#operator/' /etc/passwd
sed -i 's/sync/#sync/'         /etc/passwd
sed -i 's/halt/#halt/'         /etc/passwd
sed -i 's/ftp/#ftp/'           /etc/passwd


##### Add "suser" #####
useradd -u 1000 suser
echo 'skt7979' | passwd --stdin suser
echo -e 'suser\tALL=(ALL)\tNOPASSWD:ALL' > /etc/sudoers.d/suser


##### Passwd policy with /etc/login.defs #####
# PASS_MAX_DAYS   70
# PASS_MIN_DAYS   7
# PASS_MIN_LEN    10
sed -i '/^PASS_MAX_DAYS/ {s/[0-9]\{1,\}/70/}' /etc/login.defs
sed -i '/^PASS_MIN_DAYS/ {s/[0-9]\{1,\}/7/}'  /etc/login.defs
sed -i '/^PASS_MIN_LEN/  {s/[0-9]\{1,\}/10/}' /etc/login.defs
echo SULOG_FILE /var/log/sulog >> /etc/login.defs


##### Permission #####
touch /etc/hosts.equiv
chmod 000 /etc/hosts.equiv
touch /root/.rhosts
chmod 000 /root/.rhosts
chmod 640 /etc/rsyslog.conf
#chown -R root. /var/log/cups
chown root.wheel /bin/su
chmod 4750 /bin/su
chmod -s /usr/bin/newgrp
chmod -s /sbin/unix_chkpwd


##### SSH configuration #####
#sed -i 's/\#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i '/PermitEmptyPasswords/ {s/^#//}'            /etc/ssh/sshd_config
#echo "AllowGroups wheel" >> /etc/ssh/sshd_config


##### pam_tally (RHEL 8) #####
# /etc/pam.d/su
sed -i '/#auth\t\trequired\tpam_wheel.so/ {s/#auth/auth/}' /etc/pam.d/su
# /etc/pam.d/login
echo -e "auth\trequired\tpam_securetty.so" >> /etc/pam.d/login
touch /etc/securetty


##### kdump settings #####
sed -i '/^core_collector/ {s/-l/-c/}' /etc/kdump.conf


##### /etc/profile #####
cat << EOF >> /etc/profile

# Added for SKT
umask 022
export HISTSIZE=5000
export HISTTIMEFORMAT='%F %T '
TMOUT=900
export TMOUT
set -o vi
alias vi='vim'
EOF


##### /etc/logrotate.conf #####
sed -i 's/^weekly/monthly/;s/rotate\ 4/rotate\ 12/' /etc/logrotate.conf
sed -i 's/0664/0600/'                               /etc/logrotate.conf

exit
%end
