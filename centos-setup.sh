#!/bin/bash
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4 foldmethod=marker
# ----------------------------------------------------------------------
# Author:   DeaDSouL (Mubarak Alrashidi)
# URL:      https://unix.cafe/wp/en/2020/07/setup-a-minimal-lamp-server-for-loganalyzer-on-centos-8/
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

# If your interface is not enabled on boot #{{{
#   sed -i 's/ONBOOT=no/ONBOOT="yes"/g' /etc/sysconfig/network-scripts/ifcfg-*
#   ifup enp0s8
#}}}

# setting 'rsyslog' password #{{{
echo -e '\n\nWhat is the database password you would like to use for "rsyslog" user?\n'
RSYSPASS=''; RSYSPASS2=' '
while [ "$RSYSPASS" != "$RSYSPASS2" -o -z "$RSYSPASS" ]; do
    echo 'Password does not match or it is empty!!'
    read -sp 'Enter password: ' RSYSPASS
    echo ''
    read -sp 'Re-enter password: ' RSYSPASS2
done
echo -e '\n'
#}}}

# install required packages & repos #{{{
dnf --refresh update -y
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
dnf update -y
dnf install -y mariadb mariadb-server rsyslog-mysql httpd php php-mysqlnd php-gd http://rpms.remirepo.net/enterprise/remi-release-8.rpm
dnf config-manager --set-disabled remi-modular remi-safe
dnf install phpMyAdmin --enablerepo=remi -y
#}}}

# enable & start services #{{{
systemctl enable --now httpd.service
systemctl enable --now mariadb.service
#}}}

# creating databases and adding user #{{{
mysql -u root < /usr/share/doc/rsyslog/mysql-createDB.sql
mysql -u root -e 'CREATE DATABASE IF NOT EXISTS Loganalyzer;'
mysql -u root -e "GRANT ALL ON Syslog.* TO 'rsyslog'@'localhost' IDENTIFIED BY '$RSYSPASS';"
mysql -u root -e 'GRANT ALL ON Loganalyzer.* TO "rsyslog"@"localhost";'
mysql -u root -e 'FLUSH PRIVILEGES;'
#}}}

# configuring rsyslog.conf #{{{
cp -p /etc/rsyslog.conf{,.bkp}

sed -i 's/#module(load="imudp") # needs to be done just once/module(load="imudp") # needs to be done just once/g' /etc/rsyslog.conf
sed -i 's/#input(type="imudp" port="514")/input(type="imudp" port="514")/g' /etc/rsyslog.conf
sed -i 's/#module(load="imtcp") # needs to be done just once/module(load="imtcp") # needs to be done just once/g' /etc/rsyslog.conf
sed -i 's/#input(type="imtcp" port="514")/input(type="imtcp" port="514")/g' /etc/rsyslog.conf
echo -e "\n\n# Adding logs to MariaDB\nmodule(load=\"ommysql\")\n*.* :ommysql:127.0.0.1,Syslog,rsyslog,$RSYSPASS\n" >> /etc/rsyslog.conf

systemctl restart rsyslog
#}}}

# adding the needed firewall rules #{{{
firewall-cmd --permanent --new-service=rsyslog
firewall-cmd --permanent --service=rsyslog --set-description="Rsyslog Listener Service"
firewall-cmd --permanent --service=rsyslog --set-short=rsyslog
firewall-cmd --permanent --service=rsyslog --add-port=514/{tcp,udp}
firewall-cmd --permanent --add-service={http,https,rsyslog}
firewall-cmd --reload
#}}}

# download & prepare loganalyzer for installation #{{{
wget http://download.adiscon.com/loganalyzer/loganalyzer-4.1.10.tar.gz -P /tmp
tar -xzvf /tmp/loganalyzer-*.tar.gz -C /tmp/
mkdir /var/www/html/loganalyzer
cp -pr /tmp/loganalyzer-*/src/* /var/www/html/loganalyzer
cp -p /tmp/loganalyzer-*/contrib/configure.sh /var/www/html/loganalyzer
cd /var/www/html/loganalyzer
bash configure.sh
chcon -h -t httpd_sys_script_rw_t config.php
#}}}

# configuring phpMyAdmin #{{{
sed -i 's/   AddDefaultCharset UTF-8/   AddDefaultCharset UTF-8\n\n   <IfModule mod_authz_core.c>\n     # Apache 2.4\n     <RequireAny>\n       Require all granted\n     <\/RequireAny>\n   <\/IfModule>\n   <IfModule !mod_authz_core.c>\n     # Apache 2.2\n     Order Deny,Allow\n     Deny from All\n     Allow from 127.0.0.1\n     Allow from ::1\n   <\/IfModule>/g' /etc/httpd/conf.d/phpMyAdmin.conf
systemctl restart httpd.service
#}}}

# securing MariaDB #{{{
mysql_secure_installation
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
echo -e "    Database Password: $RSYSPASS"
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
echo -e "    Database Password: $RSYSPASS"
echo -e "    Enable Row Counting: yes\n"
#}}}
