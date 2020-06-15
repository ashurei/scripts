#!/bin/bash
# Script Code By OST(Open Source Technology Co.)
# Edited by rockplace
# 2017.05.04 Edited by anjae83
# 2017.09.29 Edited by anjae83 - kernel-2.6.32-696.10.2.el6
# 2020.04.10 Modify by ashurei
# ===========================================================

########## systemctl disable list ############################
#systemctl disable firewalld
systemctl disable NetworkManager
systemctl disable postfix
systemctl disable rhsmcertd


### SELINUX disable
#sed -i -e 's/\(^SELINUX=\)enforcing$/\1disabled/' /etc/selinux/config


### Configure yum repository
if [ ! -e /etc/yum.repos.d/local.repo ]
then
touch /etc/yum.repos.d/local.repo
echo "[DMZ-repo]"  >> /etc/yum.repos.d/local.repo
echo "name=DMZ repository" >> /etc/yum.repos.d/local.repo
echo "baseurl=file:///mnt/cdrom" >> /etc/yum.repos.d/local.repo
echo "enabled=1" >> /etc/yum.repos.d/local.repo
echo "gpgcheck=0" >> /etc/yum.repos.d/local.repo
#echo "gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release" >> /etc/yum.repos.d/dmz.repo
fi


### Create for connection warning messages
cat > /etc/motd << EOF3
************************ Warning **********************************
  
  This System is strictly restricted to authorized users only.
  Any illegal access or use shall be punished with a related-law.

                          SK Telecom

*******************************************************************

EOF3
echo "Banner /etc/motd" >> /etc/ssh/sshd_config


### Adding internal NTP Server
#ntp1="server 0.rhel.pool.ntp.org"
#ntp2="server 1.rhel.pool.ntp.org"
#ntp3="server 2.rhel.pool.ntp.org"
#ntp4="server 3.rhel.pool.ntp.org"

#cat /etc/ntp.conf |grep "$ntp1" |grep -v "^#"
#if [ $? == "0" ]
#then
#sed -i 's/server 0.rhel.pool.ntp.org/server 112.106.131.140/' /etc/ntp.conf
#fi

#cat /etc/ntp.conf |grep "$ntp2" |grep -v "^#"
#if [ $? == "0" ]
#then
#sed -i 's/server 1.rhel.pool.ntp.org/#server 1.rhel.pool.ntp.org/' /etc/ntp.conf
#fi

#cat /etc/ntp.conf |grep "$ntp3" |grep -v "^#"
#if [ $? == "0" ]
#then
#sed -i 's/server 2.rhel.pool.ntp.org/#server 2.rhel.pool.ntp.org/' /etc/ntp.conf
#fi

#cat /etc/ntp.conf |grep "$ntp4" |grep -v "^#"
#if [ $? == "0" ]
#then
#sed -i 's/server 3.rhel.pool.ntp.org/#server 3.rhel.pool.ntp.org/' /etc/ntp.conf
#fi


### ntp slew option
sed -i 's/OPTIONS="-u ntp:ntp -p \/var\/run\/ntpd.pid -g"/#OPTIONS="-u ntp:ntp -p \/var\/run\/ntpd.pid -g"/g' /etc/sysconfig/ntpd
echo "OPTIONS=\"-u ntp:ntp -p /var/run/ntpd.pid -g -x\"" >> /etc/sysconfig/ntpd


############## Modify for system-auth,password-auth pam_tally2 ##############
mkdir -p /root/backup
cp /etc/pam.d/system-auth  /root/backup/system-auth.org
cat /etc/pam.d/system-auth |grep pam_tally2

if [ $? == "1" ]
then
sed -i -e '4 i\auth        required      pam_tally2.so deny=4  unlock_time=1800' /etc/pam.d/system-auth
sed -i -e '11 i\account     required      pam_tally2.so' /etc/pam.d/system-auth
sed -i 's/retry=3/retry=3 dcredit=-1 lcredit=-1 ocredit=-1/' /etc/pam.d/system-auth
sed -i 's/use_authtok/use_authtok remember=2/' /etc/pam.d/system-auth
fi

cp /etc/pam.d/password-auth  /root/backup/password-auth.org
cat /etc/pam.d/password-auth |grep pam_tally2

if [ $? == "1" ]
then
sed -i -e '4 i\auth        required      pam_tally2.so deny=4  unlock_time=1800' /etc/pam.d/password-auth
sed -i -e '11 i\account     required      pam_tally2.so' /etc/pam.d/password-auth
sed -i 's/retry=3/retry=3 dcredit=-1 lcredit=-1 ocredit=-1/' /etc/pam.d/password-auth
sed -i 's/use_authtok/use_authtok remember=2/' /etc/pam.d/password-auth
fi


##########  rc.local 추가 #################
echo "chmod 600 /var/log/wtmp" >> /etc/rc.local


########## file permission #####################
chmod 444 /etc/passwd
chmod 600 /etc/passwd-
chmod 600 /var/log/wtmp 
chmod 600 /var/log/dmesg
chmod 600 /var/log/messages
chmod 600 /var/log/lastlog
chmod 700 /boot
touch /etc/cron.allow
chmod 755 /etc/cron.allow
chmod 755 /etc/cron.deny
chmod go-rwx /usr/bin/last /sbin/ifconfig /bin/su

touch /etc/hosts.equiv
chmod 000 /etc/hosts.equiv
touch /root/.rhosts
chmod 000 /root/.rhosts


######### passwd_policy config ###################
PASS1=`cat /etc/login.defs |grep -i -e PASS_MAX_DAYS |grep -iv -e "^#" | awk '{print $2}'`
PASS1_1=90

PASS2=`cat /etc/login.defs |grep -i -e PASS_WARN_AGE |grep -iv -e "^#" | awk '{print $2}'`
PASS2_1=7

PASS3=`cat /etc/login.defs |grep -i -e PASS_MIN_DAYS |grep -iv -e "^#" | awk '{print $2}'`
PASS3_1=7

PASS4=`cat /etc/login.defs |grep -i -e PASS_MIN_LEN |grep -iv -e "^#" | awk '{print $2}'`
PASS4_1=8

if [ "$PASS1" != "$PASS1_1" ] ;then
sed -i -e   's/PASS_MAX_DAYS\t'$PASS1'/PASS_MAX_DAYS\t'$PASS1_1'/g' /etc/login.defs
fi

if [ "$PASS2" != "$PASS2_1" ] ;then
sed -i -e   's/PASS_WARN_AGE\t'$PASS2'/PASS_WARN_AGE\t'$PASS2_1'/g' /etc/login.defs
fi

if [ "$PASS3" != "$PASS3_1" ] ;then
sed -i -e   's/PASS_MIN_DAYS\t'$PASS3'/PASS_MIN_DAYS\t'$PASS3_1'/g' /etc/login.defs
fi

if [ "$PASS4" != "$PASS4_1" ] ;then
sed -i -e   's/PASS_MIN_LEN\t'$PASS4'/PASS_MIN_LEN\t'$PASS4_1'/g' /etc/login.defs
fi


############# logrotate ######################################
sed -i 's/^weekly/monthly/g;s/rotate\ 4/rotate\ 12/g;;s/rotate\ 1$/rotate\ 12/g;' /etc/logrotate.conf


###### kernel patch #########
#ckernel=`uname -r`
#pkernel="2.6.32-696.1.1.el6.x86_64"

#if [ $ckernel != $pkernel ]
#then
#rpm -Uvh /root/custom/kernel-firmware-2.6.32-696.10.2.el6.noarch.rpm
#rpm -Uvh /root/custom/dracut-004-409.el6_8.2.noarch.rpm /root/custom/dracut-kernel-004-409.el6_8.2.noarch.rpm
#rpm -ivh /root/custom/kernel-2.6.32-696.10.2.el6.x86_64.rpm
#rpm -ivh /root/custom/kernel-devel-2.6.32-696.10.2.el6.x86_64.rpm
#rpm -Uvh /root/custom/kernel-headers-2.6.32-696.10.2.el6.x86_64.rpm
#fi


########## bash,glibc,ntp,openssl path ############################

#rpm -Uvh /root/custom/glibc-2.12-1.166.el6_7.3.x86_64.rpm  /root/rock/glibc-common-2.12-1.166.el6_7.3.x86_64.rpm  /root/rock/glibc-devel-2.12-1.166.el6_7.3.x86_64.rpm /root/rock/glibc-headers-2.12-1.166.el6_7.3.x86_64.rpm
#rpm -Uvh /root/custom/ntp-4.2.6p5-5.el6_7.4.x86_64.rpm /root/rock/ntpdate-4.2.6p5-5.el6_7.4.x86_64.rpm
#rpm -Uvh /root/custom/openssl-1.0.1e-42.el6_7.2.x86_64.rpm /root/rock/openssl-devel-1.0.1e-42.el6_7.2.x86_64.rpm /root/rock/openssl098e-0.9.8e-18.el6_5.2.x86_64.rpm


########## profile edit ############################
echo "TMOUT=1800" >> /etc/profile
echo "set -o vi" >> /etc/profile
echo "umask 022" >> /etc/profile


########## rsyslog.conf ###########################
echo "## kern log ##" >> /etc/rsyslog.conf
echo "kern.*		/var/log/kern.log" >> /etc/rsyslog.conf


########## syslog #################################
sed -i '6s/{/\/var\/log\/kern.log\n{/g' /etc/logrotate.d/syslog


########## control-alt-delete.conf(RHEL5,6) ###################
#sed -i 's/start on control-alt-delete/#start on control-alt-delete/g' /etc/init/control-alt-delete.conf
#sed -i 's/exec \/sbin\/shutdown -r now "Control-Alt-Delete pressed"/#exec \/sbin\/shutdown -r now "Control-Alt-Delete pressed"/g' /etc/init/control-alt-delete.conf


########## limits.conf ############################
#rm -rf /etc/security/limits.d/90-nproc.conf
#echo "*		soft	nproc	16384" >> /etc/security/limits.conf
#echo "*		hard	nproc	16384" >> /etc/security/limits.conf
#echo "*		soft	nofile	65536" >> /etc/security/limits.conf
#echo "*		hard	nofile	65536" >> /etc/security/limits.conf
#echo "*		soft	stack	10240" >> /etc/security/limits.conf
#echo "*		hard	stack	10240" >> /etc/security/limits.conf


########## delete not using user ############################
cp /etc/passwd /root/backup/passwd.org
sed -i 's/shutdown/#shutdown/' /etc/passwd
sed -i 's/operator/#operator/' /etc/passwd
sed -i 's/sync/#sync/' /etc/passwd
sed -i 's/halt/#halt/' /etc/passwd

########## rhsmd off ############################
#sed -i 's/\/usr/#\/usr/' /etc/cron.daily/rhsmd
mv /etc/cron.daily/rhsmd /root/backup/
