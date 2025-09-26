#!/bin/bash
# Create OS user
#sudo groupadd -g 1010 maria
#sudo useradd -u 1010 -g 1010 maria
sudo useradd maria

# Configure directory (/MARIA)
sudo mkdir -p /MARIA/{DATA,LOG,TMP,BACKUP}
sudo mkdir -p /MARIA/LOG/{error,slow}
sudo cp ~/mariadb-11.4.8-linux-systemd-x86_64.tar.gz /MARIA/
sudo chown maria.maria /MARIA

# Install jemalloc
#sudo yum localinstall -y ~/MariaDB/jemalloc-3.6.0-1.el7.x86_64.rpm jemalloc-devel-3.6.0-1.el7.x86_64.rpm
sudo dnf localinstall -y jemalloc-5.2.1-2.el8.x86_64 jemalloc-devel-5.2.1-2.el8.x86_64


sudo su - maria -s /bin/bash << EOF
cd /MARIA
tar xfz mariadb-11.4.8-linux-systemd-x86_64.tar.gz
ln -s mariadb-11.4.8-linux-systemd-x86_64 mariadb

# PATH (maria, tcore)
sed -i '/^PATH/s/$/:\/MARIA\/mariadb\/bin/' ~/.bash_profile
EOF

# /etc/init.d/mariadb
sudo cp /MARIA/mariadb/support-files/mysql.server /etc/init.d/mariadb
sudo sed -i '/^basedir/s/$/\/MARIA\/mariadb/' /etc/init.d/mariadb
sudo sed -i '/^datadir/s/$/\/MARIA\/DATA/' /etc/init.d/mariadb
sudo sed -i '/^init_functions/s/\""$/\-""/' /etc/init.d/mariadb
  # /etc/init.d/functions 에 log_success_msg 가 없기 때문에 제거
sudo systemctl daemon-reload

# 신규 DB 생성 및 구동
sudo su - maria -s /bin/bash <<EOF
/MARIA/mariadb/scripts/mariadb-install-db --user=maria --basedir=/MARIA/mariadb --datadir=/MARIA/DATA
EOF
sudo service mariadb start
sudo /MARIA/mariadb/bin/mariadb-secure-installation --basedir=/MARIA/mariadb --defaults-file=/etc/my.cnf << EOF
\n
y
n
EOF
#Enter y n y y y y
