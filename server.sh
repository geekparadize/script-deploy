#!/bin/bash
#
# --------------------------------------------------------------------
# This is a free shell script under GNU GPL version 3.0 or above
# -------------------------------------------------------------------------
#
# This script automatically set up a new *Debian* server (IMPORTANT : Debian!), by doing these actions :
#
# * Modification of the root password
# * Adding .email & .forward with the official root email
# * Sending an email to check sendmail
# * Adds French accents to shell
# * Define an hostname for the server
# * Creating users
# * Securing SSH
# * Update the system
# * Install unattended-upgrades
# * Install Fail2Ban
# * Install and set some security for :
# ** Apache
# *** Disable modules : userdir suexec cgi cgid dav include autoindex authn_file status env headers proxy proxy_balancer proxy_http headers
# *** Enable modules : expires rewrite setenvif ssl
# ** Mysql
# *** Execute mysql_secure_installation script
# ** PHP
# *** With modules : cli mysql curl gd mcrypt memcache memcached suhosin
# ** PHPMyAdmin
# ** ProFTPd with MySQL support
#
# @see http://plusbryan.com/my-first-5-minutes-on-a-server-or-essential-security-for-linux-servers
# For install NGinx & PHP, see :
# @see https://www.digitalocean.com/community/tutorials/how-to-install-linux-nginx-mysql-php-lemp-stack-on-debian-7

# First of all, we check if the user is root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Changing the password of the root user
read -e -p "Do you want to change the root password? [Y/n] : " change_password
if [[ ("$change_password" == "y" || "$change_password" == "Y" || "$change_password" == "") ]]; then
    passwd
fi

# Installing Postfix
read -e -p "Do you want to install PostFix? [Y/n] : " install_postfix
if [[ ("$install_postfix" == "y" || "$install_postfix" == "Y" || "$install_postfix" == "") ]]; then
   apt-get remove exim4-base exim4-config exim4-daemon-light
   apt-get --yes install postfix
   # We only want to send emails
   sed -i "s/inet_interfaces = all/inet_interfaces = loopback-only/" /etc/postfix/main.cf
fi

read -e -p "Admin contact email : " root_email

if [[ "$root_email" != "" ]]; then
    echo $root_email > ~/.email
    echo $root_email > ~/.forward

    read -e -p "Send an mail to test the smtp service? [Y/n] : " send_email
    if [[ ("$send_email" == "y" || "$send_email" == "Y" || "$send_email" == "") ]]; then
        echo "This is a mail test for the SMTP Service." > /tmp/email.message
        echo "You should receive this !" >> /tmp/email.message
        echo "" >> /tmp/email.message
        echo "Cheers" >> /tmp/email.message
        mail -s "SMTP Testing" $root_email < /tmp/email.message

        rm -f /tmp/email.message
        echo "Mail sent"
    fi
fi

# Adding French accents to bash
grep -q 'export LANG=fr_FR.UTF-8' ~/.bashrc || echo "export LANG=fr_FR.UTF-8" >> ~/.bashrc

# And adding it for all the newly created users :
grep -q 'export LANG=fr_FR.UTF-8' /etc/skel/.bashrc || echo "export LANG=fr_FR.UTF-8" >> /etc/skel/.bashrc

echo "Updating Server name"
read -e -p "New server name (like srv.company.tld) : " server_name
if [[ "$server_name" != "" ]]; then
    echo $server_name > /etc/hostname
    IP=$(ip addr show | grep eth0 | grep inet | tr -s " " | cut -f3 -d " " | cut -f1 -d "/")

    hosts_ip=$(grep -q $IP /etc/hosts)
    if [[ "$hosts_ip" != "" ]]; then
        sed -i "s/$IP.*/$IP $server_name/" /etc/hosts
    else
        echo "$IP $server_name" >> /etc/hosts
    fi

    hostname $server_name

    /etc/init.d/hostname.sh
fi

# Creating multiple users
create_user=true
while $create_user; do
    read -e -p "Create a new user? [y/N] : " new_user

    if [[ ("$new_user" == "y" || "$new_user" == "Y") ]]; then
        read -e -p "Username : " user_name
        adduser $user_name
    else
        create_user=false
    fi
done

# SSH Server
echo "Improving security on SSH"

echo " * Allow AuthorizedKeyFiles"
sed -i "s/#AuthorizedKeysFile/AuthorizedKeysFile/" /etc/ssh/sshd_config

echo " * Disallow X11Forwarding"
sed -i "s/X11Forwarding yes/X11Forwarding no/" /etc/ssh/sshd_config

echo " * Removing Root Login"
sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config

read -e -p "SSH Allowed users (space separated) : " ssh_users
if [[ $ssh_users ]]; then
    echo "AllowUsers $ssh_users" >> /etc/ssh/sshd_config
fi

/etc/init.d/ssh restart

read -e -p "Force update the server? [Y/n] : " force_update
if [[ ("$force_update" == "y" || "$force_update" == "Y" || "$force_update" == "") ]]; then
    apt-get --yes update && apt-get --yes upgrade && apt-get dist-upgrade
fi

read -e -p "Automate installation of new upgrades? [Y/n] : " install_unattended
if [[ ("$install_unattended" == "y" || "$install_unattended" == "Y" || "$install_unattended" == "") ]]; then
    apt-get --yes install unattended-upgrades
fi

read -e -p "Install Fail2ban? [Y/n] : " install_fail2ban
if [[ ("$install_fail2ban" == "y" || "$install_fail2ban" == "Y" || "$install_fail2ban" == "") ]]; then
    apt-get --yes install fail2ban
fi

read -e -p "Install Apache? [Y/n] : " install_apache
if [[ ("$install_apache" == "y" || "$install_apache" == "Y" || "$install_apache" == "") ]]; then
    apt-get --yes install apache2
    a2dismod userdir suexec cgi cgid dav include autoindex authn_file status env headers proxy proxy_balancer proxy_http headers
    a2enmod expires rewrite setenvif ssl

    sed -i "s/ServerTokens.*/ServerTokens Prod/g" /etc/apache2/conf.d/security
    sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf.d/security

    /etc/init.d/apache2 restart
fi

read -e -p "Install MySQL? [Y/n] : " install_mysql
if [[ ("$install_mysql" == "y" || "$install_mysql" == "Y" || "$install_mysql" == "") ]]; then
    apt-get --yes install mysql-server

    read -e -p "Execute mysql_secure_installation ? [Y/n] : " mysql_secure
    if [[ ("$mysql_secure" == "y" || "$mysql_secure" == "Y" || "$mysql_secure" == "") ]]; then
        mysql_secure_installation
    fi
fi

read -e -p "Install PHP? [Y/n] : " install_php
if [[ ("$install_php" == "y" || "$install_php" == "Y" || "$install_php" == "") ]]; then
    apt-get --yes install php5 libapache2-mod-php5 php5-cli php5-mysql php5-curl php5-gd php5-mcrypt php5-memcache php5-memcached

    # General settings
    sed -i "s/expose_php.*/expose_php = Off/" /etc/php5/apache2/php.ini
    sed -i "s/disable_functions.*/disable_functions = exec,system,shell_exec,passthru/" /etc/php5/apache2/php.ini
    sed -i "s/register_globals.*/register_globals = Off/" /etc/php5/apache2/php.ini

    # Session specific
    sed -i "s/session.use_only_cookies.*/session.use_only_cookies = 1/" /etc/php5/apache2/php.ini
    sed -i "s/session.cookie_httponly.*/session.cookie_httponly = 1/" /etc/php5/apache2/php.ini
    sed -i "s/session.use_trans_sid.*/session.use_trans_sid = 0/" /etc/php5/apache2/php.ini

    # For CLI :
    sed -i "s/disable_functions.*/disable_functions = exec,system,shell_exec,passthru/" /etc/php5/cli/php.ini
    sed -i "s/register_globals.*/register_globals = Off/" /etc/php5/cli/php.ini

    read -e -p "Install PHPMyAdmin? [Y/n] : " install_pma
    if [[ ("$install_pma" == "y" || "$install_pma" == "Y" || "$install_pma" == "") ]]; then
        apt-get --yes install phpmyadmin
    fi

    /etc/init.d/apache2 restart
fi

read -e -p "Install ProFTPd (With MySQL support)? [Y/n] : " install_proftpd
if [[ ("$install_proftpd" == "y" || "$install_proftpd" == "Y" || "$install_proftpd" == "") ]]; then
    apt-get --yes install proftpd-mod-mysql

    sed -i "s/#LoadModule mod_sql.c/LoadModule mod_sql.c/" /etc/proftpd/modules.conf
    sed -i "s/#LoadModule mod_sql_mysql.c/LoadModule mod_sql_mysql.c/" /etc/proftpd/modules.conf

    sed -i "s/#Include \/etc\/proftpd\/sql.conf/Include \/etc\/proftpd\/sql.conf/" /etc/proftpd/proftpd.conf

    # Creating proftpd.sql file
    read -e -p "ProFTPd DataBase name? [proftpd] : " proftpd_database
    if [[ "$proftpd_database" == "" ]]; then
        proftpd_database="proftpd"
    fi

    read -e -p "ProFTPd Username? [proftpd] : " proftpd_user
    if [[ "$proftpd_user" == "" ]]; then
        proftpd_user="proftpd"
    fi

    while true; do
        read -e -p "ProFTPd User password for $proftpd_user ? : " -s proftpd_passwd
        if [[ "$proftpd_passwd" != "" ]]; then
            break
        fi
    done

    echo "CREATE DATABASE $proftpd_database;" > /tmp/proftpd.create.sql
    echo "" >> /tmp/proftpd.create.sql

    read -e -p "Create a specific ProFTPd user? [Y/n] : " proftpd_new_user
    if [[ ("$proftpd_new_user" == "y" || "$proftpd_new_user" == "Y" || "$proftpd_new_user" == "") ]]; then
        echo "GRANT SELECT, INSERT, UPDATE, DELETE ON $proftpd_database.* TO '$proftpd_user'@'localhost' IDENTIFIED BY '$proftpd_passwd';" >> /tmp/proftpd.create.sql
        echo "FLUSH PRIVILEGES;" >> /tmp/proftpd.create.sql
        echo "" >> /tmp/proftpd.create.sql
    fi

    proftpd_default_user=$(id -u www-data)
    proftpd_default_group=$(id -g www-data)

    echo "USE $proftpd_database;" >> /tmp/proftpd.create.sql
    echo "" >> /tmp/proftpd.create.sql
    echo "CREATE TABLE ftpgroup (" >> /tmp/proftpd.create.sql
    echo "    groupname varchar(16) NOT NULL default ''," >> /tmp/proftpd.create.sql
    echo "    gid smallint(6) NOT NULL default '$proftpd_default_group'," >> /tmp/proftpd.create.sql
    echo "    members varchar(16) NOT NULL default ''," >> /tmp/proftpd.create.sql
    echo "    KEY groupname (groupname)" >> /tmp/proftpd.create.sql
    echo ") ENGINE=MyISAM COMMENT='ProFTP group table';" >> /tmp/proftpd.create.sql
    echo "" >> /tmp/proftpd.create.sql
    echo "CREATE TABLE ftpuser (" >> /tmp/proftpd.create.sql
    echo "    id int(10) unsigned NOT NULL auto_increment," >> /tmp/proftpd.create.sql
    echo "    userid varchar(32) NOT NULL default ''," >> /tmp/proftpd.create.sql
    echo "    passwd varchar(32) NOT NULL default ''," >> /tmp/proftpd.create.sql
    echo "    uid smallint(6) NOT NULL default '$proftpd_default_user'," >> /tmp/proftpd.create.sql
    echo "    gid smallint(6) NOT NULL default '$proftpd_default_group'," >> /tmp/proftpd.create.sql
    echo "    homedir varchar(255) NOT NULL default ''," >> /tmp/proftpd.create.sql
    echo "    shell varchar(16) NOT NULL default '/sbin/nologin'," >> /tmp/proftpd.create.sql
    echo "    count int(11) NOT NULL default '0'," >> /tmp/proftpd.create.sql
    echo "    accessed datetime NOT NULL default '0000-00-00 00:00:00'," >> /tmp/proftpd.create.sql
    echo "    modified datetime NOT NULL default '0000-00-00 00:00:00'," >> /tmp/proftpd.create.sql
    echo "    PRIMARY KEY (id)," >> /tmp/proftpd.create.sql
    echo "    UNIQUE KEY userid (userid)" >> /tmp/proftpd.create.sql
    echo ") ENGINE=MyISAM COMMENT='ProFTP user table';" >> /tmp/proftpd.create.sql
    echo "" >> /tmp/proftpd.create.sql
    echo "INSERT INTO ftpgroup (groupname, gid, members) VALUES ('www-data', $proftpd_default_group, 'www-data');" >> /tmp/proftpd.create.sql

    # Creating sql.conf file
    echo "#" > /etc/proftpd/sql.conf
    echo "# Proftpd sample configuration for SQL-based authentication." >> /etc/proftpd/sql.conf
    echo "#" >> /etc/proftpd/sql.conf
    echo "# (This is not to be used if you prefer a PAM-based SQL authentication)" >> /etc/proftpd/sql.conf
    echo "#" >> /etc/proftpd/sql.conf
    echo "<IfModule mod_sql.c>" >> /etc/proftpd/sql.conf
    echo "    DefaultRoot ~" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    #" >> /etc/proftpd/sql.conf
    echo "    # Choose a SQL backend among MySQL or PostgreSQL." >> /etc/proftpd/sql.conf
    echo "    # Both modules are loaded in default configuration, so you have to specify the backend" >> /etc/proftpd/sql.conf
    echo "    # or comment out the unused module in /etc/proftpd/modules.conf." >> /etc/proftpd/sql.conf
    echo "    # Use 'mysql' or 'postgres' as possible values." >> /etc/proftpd/sql.conf
    echo "    #" >> /etc/proftpd/sql.conf
    echo "    SQLBackend        mysql" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    #" >> /etc/proftpd/sql.conf
    echo "    #SQLEngine on" >> /etc/proftpd/sql.conf
    echo "    #SQLAuthenticate on" >> /etc/proftpd/sql.conf
    echo "    #" >> /etc/proftpd/sql.conf
    echo "    # Use both a crypted or plaintext password" >> /etc/proftpd/sql.conf
    echo "    SQLAuthTypes            Plaintext Crypt" >> /etc/proftpd/sql.conf
    echo "    SQLAuthenticate         users groups" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    #" >> /etc/proftpd/sql.conf
    echo "    # Connection" >> /etc/proftpd/sql.conf
    echo "    SQLConnectInfo  $proftpd_database@localhost $proftpd_user $proftpd_passwd" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    #" >> /etc/proftpd/sql.conf
    echo "    # Describes both users/groups tables" >> /etc/proftpd/sql.conf
    echo "    #" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    # Here we tell ProFTPd the names of the database columns in the 'usertable'" >> /etc/proftpd/sql.conf
    echo "    # we want it to interact with. Match the names with those in the db" >> /etc/proftpd/sql.conf
    echo "    SQLUserInfo     ftpuser userid passwd uid gid homedir shell" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    # Here we tell ProFTPd the names of the database columns in the 'grouptable'" >> /etc/proftpd/sql.conf
    echo "    # we want it to interact with. Again the names match with those in the db" >> /etc/proftpd/sql.conf
    echo "    SQLGroupInfo    ftpgroup groupname gid members" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    # set min UID and GID - otherwise these are 999 each" >> /etc/proftpd/sql.conf
    echo "    SQLMinID        $proftpd_default_user" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    # create a user's home directory on demand if it doesn't exist" >> /etc/proftpd/sql.conf
    echo "    CreateHome on" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    # Update count every time user logs in" >> /etc/proftpd/sql.conf
    echo "    SQLLog PASS updatecount" >> /etc/proftpd/sql.conf
    echo "    SQLNamedQuery updatecount UPDATE \"count=count+1, accessed=now() WHERE userid='%u'\" ftpuser" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    # Update modified everytime user uploads or deletes a file" >> /etc/proftpd/sql.conf
    echo "    SQLLog  STOR,DELE modified" >> /etc/proftpd/sql.conf
    echo "    SQLNamedQuery modified UPDATE \"modified=now() WHERE userid='%u'\" ftpuser" >> /etc/proftpd/sql.conf
    echo "" >> /etc/proftpd/sql.conf
    echo "    RootLogin off" >> /etc/proftpd/sql.conf
    echo "    RequireValidShell off" >> /etc/proftpd/sql.conf
    echo "</IfModule>" >> /etc/proftpd/sql.conf

    # now execute sql as root in database!
    echo "Please indicate your MySQL root password"
    mysql -u root -p < /tmp/proftpd.create.sql

    rm -f /tmp/proftpd.create.sql

    /etc/init.d/proftpd restart
fi

exit 0;
