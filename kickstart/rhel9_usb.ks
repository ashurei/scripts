########################################################
# Description : Kickstart for Redhat Linux 9.8
# Create DATE : 2022.03.11
# Last Update DATE : 2025.09.19 by ashurei
# Copyright (c) ashurei@sktelecom.com, 2022
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
cp -r /run/install/repo/custom/rpm /mnt/sysroot/root/
%end


### Install packages ============================================================================= #
%packages --ignoremissing
@^minimal-environment
gcc
krb5-devel
man-pages
man-pages-overrides
net-tools
openssl-devel
perl
sysstat
vim-enhanced
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


##### Chrony configuration #####
sed -i '/^pool /s/pool/#pool/' /etc/chrony.conf
sed -i '/^#pool /a\pool 60.30.131.100 iburst' /etc/chrony.conf


##### Change collection interval of the SAR #####
# Change per 10mins to per 1min
sed -i '/^Description/s/10/1/' /usr/lib/systemd/system/sysstat-collect.timer
sed -i '/^OnCalendar/s/\:00\/10/\:00\/1/' /usr/lib/systemd/system/sysstat-collect.timer


##### Local yum repository #####
mkdir -p /etc/yum.repos.d/org
mv /etc/yum.repos.d/Rocky-*.repo /etc/yum.repos.d/org/
cat << EOF > /etc/yum.repos.d/tb-ossrepo.repo
[SKT-TB-RHEL$releasever-baseos]
name=RHEL-$releasever-baseos
baseurl=http://60.30.131.100/repos/rhel/$releasever/rhel-$releasever-for-x86_64-baseos-rpms
enabled=1
gpgcheck=0

[SKT-TB-RHEL$releasever-appstream]
name=RHEL-$releasever-appstream
baseurl=http://60.30.131.100/repos/rhel/$releasever/rhel-$releasever-for-x86_64-appstream-rpms
enabled=1
gpgcheck=0

[SKT-TB-RHEL$releasever-ha]
name=RHEL-$releasever-ha
baseurl=http://60.30.131.100/repos/rhel/$releasever/rhel-$releasever-for-x86_64-highavailability-rpms
enabled=1
gpgcheck=0

[SKT-TB-EPEL$releasever]
name=EPEL-$releasever
baseurl=http://60.30.131.100/repos/epel/$releasever
enabled=1
gpgcheck=0
EOF


##### Kernel patch #####
RPMDIR="/root/rpm"
rpm -Uvh ${RPMDIR}/kernel-5.14.0-687.23.1.el9_8.x86_64.rpm ${RPMDIR}/kernel-core-5.14.0-687.23.1.el9_8.x86_64.rpm ${RPMDIR}/kernel-modules-5.14.0-687.23.1.el9_8.x86_64.rpm ${RPMDIR}/kernel-modules-core-5.14.0-687.23.1.el9_8.x86_64.rpm
rpm -Uvh ${RPMDIR}/kernel-tools-5.14.0-687.23.1.el9_8.x86_64.rpm ${RPMDIR}/kernel-tools-libs-5.14.0-687.23.1.el9_8.x86_64.rpm


# Security #

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
cp /etc/motd /etc/issue.net


##### Delete not using user #####
mkdir /root/backup
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
# PASS_MAX_DAYS   90
# PASS_MIN_DAYS   1
# PASS_MIN_LEN    9
sed -i '/^PASS_MAX_DAYS/ {s/[0-9]\{1,\}/90/}' /etc/login.defs
sed -i '/^PASS_MIN_DAYS/ {s/[0-9]\{1,\}/1/}' /etc/login.defs
sed -i '/^PASS_MIN_LEN/  {s/[0-9]\{1,\}/9/}' /etc/login.defs
echo SULOG_FILE /var/log/sulog >> /etc/login.defs


##### Permission #####
touch /etc/hosts.equiv
chmod 000 /etc/hosts.equiv
touch /root/.rhosts
chmod 000 /root/.rhosts
chmod 640 /etc/rsyslog.conf
chown root.wheel /bin/su
chmod 4750 /bin/su
chmod 4750 /usr/bin/crontab
chmod 600 /var/log/wtmp*
chmod 600 /etc/systemd/*.conf
chmod 600 /etc/systemd/system
chmod 600 /etc/systemd/user


### /etc/rsyslog.conf
echo '*.alert /dev/console' >> /etc/rsyslog.conf


##### SSH root access configuration #####
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
#echo "AllowGroups wheel" >> /etc/ssh/sshd_config


##### pam_tally #####
# system-auth
sudo sed -i '10d' /etc/pam.d/system-auth
sudo sed -i '9a\password    requisite     pam_pwhistory.so remember=5 use_authtok enforce_for_root' /etc/pam.d/system-auth

##### kdump settings #####
sed -i '/^core_collector/ {s/-l/-c/}' /etc/kdump.conf


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
sed -i 's/0664/0600/' /etc/logrotate.conf

exit
%end
