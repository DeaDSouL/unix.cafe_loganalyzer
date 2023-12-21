#!/bin/bash
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4 foldmethod=marker
# ----------------------------------------------------------------------
# Author:   DeaDSouL (Mubarak Alrashidi)
# URL:      https://unix.cafe/wp/en/2020/07/setup-a-minimal-lamp-server-for-loganalyzer-on-debian-10-buster/
# GitLab:   https://gitlab.com/unix.cafe/loganalyzer
# Twitter:  https://twitter.com/_DeaDSouL_
# License:  GPLv3
# ----------------------------------------------------------------------

# make sure we have root's power
if [ $UID -ne 0 ]; then #{{{
    echo 'Script should be executed by "root"'
    echo 'Or prefixed with "sudo".'
    exit 1
fi #}}}

# install required packages & repos #{{{
echo 'deb http://deb.debian.org/debian buster-backports main contrib non-free' > /etc/apt/sources.list.d/backports.list
apt update ; apt upgrade -y
apt install -y mariadb-client mariadb-server apache2 php libapache2-mod-php php-gd php-mysql
#}}}

# enable & start services #{{{
systemctl enable --now apache2.service
systemctl enable --now mariadb.service
#}}}

# installing phpmyadmin #{{{
apt -t buster-backports install php-twig -y
apt install phpmyadmin -y
#}}}

# configuring rsyslog.conf #{{{
apt install -y rsyslog-mysql

cp -p /etc/rsyslog.conf{,.bkp}

sed -i 's/#module(load="imudp")/module(load="imudp")/g' /etc/rsyslog.conf
sed -i 's/#input(type="imudp" port="514")/input(type="imudp" port="514")/g' /etc/rsyslog.conf
sed -i 's/#module(load="imtcp")/module(load="imtcp")/g' /etc/rsyslog.conf
sed -i 's/#input(type="imtcp" port="514")/input(type="imtcp" port="514")/g' /etc/rsyslog.conf

systemctl restart rsyslog.service
#}}}

# creating databases and users #{{{
#mariadb -u root -e "CREATE DATABASE IF NOT EXISTS Syslog;"
mariadb -u root -e "CREATE DATABASE IF NOT EXISTS Loganalyzer;"
mariadb -u root -e "GRANT ALL ON Syslog.* TO 'rsyslog'@'localhost';"
mariadb -u root -e "GRANT ALL ON Loganalyzer.* TO 'rsyslog'@'localhost';"
mariadb -u root -e "FLUSH PRIVILEGES;"
#}}}

# Which auth for root to use? #{{{
echo -e '\n\n----------------------------------------------------------------------\n'
echo -e 'By default Debian uses "unix_socket". Which allows you to login'
echo -e 'to MariaDB from terminal without the need of entering any password'
echo -e 'as long as you are logged-in with "root". Yet you cannot use the'
echo -e 'MariaDB "root" user to login via phpmyadmin. Since it requires'
echo -e 'a password to authenticate against.\n'
echo -e 'So, which one would you like to use?'
echo -e '\t1) unix_socket (default)'
echo -e '\t2) mysql_native_password\n'
read -p '1 or 2: ' DBAUTH
while [ "$DBAUTH" != 1 -a "$DBAUTH" != 2 ]; do
    echo -e 'Invalid choise!'
    echo -e '\t1) unix_socket (default)'
    echo -e '\t2) mysql_native_password\n'
    read -p '1 or 2: ' DBAUTH
    echo ''
done

if [ "$DBAUTH" == 1 ]; then
    # auth root with unix login
    mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH unix_socket;"
elif [ "$DBAUTH" == 2 ]; then
    # auth root with pass
    mariadb -u root -e 'UPDATE mysql.user SET plugin = "mysql_native_password" WHERE User = "root";' 
    mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'toor';"
    echo -e '\n\nThe MariaDB root password is: toor\n'
    mysql_secure_installation
fi
echo -e '\n'
systemctl restart mariadb.service
#}}}

# download & prepare loganalyzer for installation #{{{
wget http://download.adiscon.com/loganalyzer/loganalyzer-4.1.10.tar.gz -P /tmp
tar -xzvf /tmp/loganalyzer-*.tar.gz -C /tmp/
mkdir /var/www/html/loganalyzer
cp -pr /tmp/loganalyzer-*/src/* /var/www/html/loganalyzer
cp -p /tmp/loganalyzer-*/contrib/configure.sh /var/www/html/loganalyzer
cd /var/www/html/loganalyzer
bash configure.sh
#chcon -h -t httpd_sys_script_rw_t config.php
#}}}

# adding the needed firewall rules #{{{
apt install -y ufw
systemctl enable --now ufw.service
ufw enable
ufw allow in "WWW Full" comment 'http & https'
ufw allow in 514/tcp comment 'rsyslog (tcp)'
ufw allow in 514/udp comment 'rsyslog (udp)'
ufw allow in SSH
ufw reload
#}}}

# printing some info #{{{
echo -e "\nNow, go to http://localhost/loganalyzer/install.php"
echo -e "in step 3"
echo -e "  User Database Options"
echo -e "    Enable User Database: yes"
echo -e "    Database Host: localhost"
echo -e "    Port: 3306"
echo -e "    Database Name: Loganalyzer"
echo -e "    Table prefix: "
echo -e "    Database User: rsyslog"
echo -e "    Database Password: the rsyslog-mysql password you've chosen"
echo -e "in step 7"
echo -e "  First Syslog Source"
echo -e "    Source Type: MYSQL Native"
echo -e "    Select View: Syslog Fields"
echo -e "  Database Type Options"
echo -e "    Table type: MonitorWare"
echo -e "    Database Host: localhost"
echo -e "    Database Name: Syslog"
echo -e "    Database Tablename: SystemEvents"
echo -e "    Database User: rsyslog"
echo -e "    Database Password: the rsyslog-mysql password you've chosen"
echo -e "    Enable Row Counting: yes\n"
#}}}
