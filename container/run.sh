#!/bin/bash
#
# Prepare our container for initial boot.

set -e 
# Redirect any output to the journal (stderr)
exec 1>&2

# writing ssmtp.conf
# Check if SMTP is enabled

echo "Editing ssmtp.conf"
if [[ "$SMTP_ENABLED" != "1" ]]; then
    echo "SMTP relay settings from cluster-admin is not enabled. Exiting."
else
    # Create or overwrite the ssmtp.conf file
    {
        echo "mailhub=${SMTP_HOST}:${SMTP_PORT}"
        echo "AuthUser=${SMTP_USERNAME}"
        echo "AuthPass=${SMTP_PASSWORD}"

        # Configure encryption based on the SMTP_ENCRYPTION setting
        if [[ "$SMTP_ENCRYPTION" == "starttls" ]]; then
            echo "UseSTARTTLS=YES"
        elif [[ "$SMTP_ENCRYPTION" == "tls" ]]; then
            echo "UseTLS=YES"
        fi

        # Optional TLS certificate verification
        if [[ "$SMTP_TLSVERIFY" == "1" ]]; then
            echo "TLS_CA_File=/etc/ssl/certs/ca-certificates.crt"
            echo "TLS_CA_Dir=/etc/ssl/certs"
        fi

        # echo "hostname=$(hostname)"
        echo "FromLineOverride=YES"
    } > /etc/ssmtp/ssmtp.conf

    echo "ssmtp.conf has been configured."
fi

echo "Updating settings for PHP APACHE ${PHP_VERSION}" && \
    sed -ri -e "s/^upload_max_filesize.*/upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}/" /etc/php/${PHP_VERSION}/apache2/php.ini \
    -e "s/^post_max_size.*/post_max_size = ${PHP_POST_MAX_SIZE}/" /etc/php/${PHP_VERSION}/apache2/php.ini \
    -e "s/^memory_limit.*/memory_limit = ${PHP_MEMORY_LIMIT}/" /etc/php/${PHP_VERSION}/apache2/php.ini \
    -e "s/^max_execution_time.*/max_execution_time = ${PHP_MAX_EXECUTION_TIME}/" /etc/php/${PHP_VERSION}/apache2/php.ini

echo "Updating settings for PHP CLI ${PHP_VERSION}" && \
    sed -ri -e "s/^upload_max_filesize.*/upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}/" /etc/php/${PHP_VERSION}/cli/php.ini \
    -e "s/^post_max_size.*/post_max_size = ${PHP_POST_MAX_SIZE}/" /etc/php/${PHP_VERSION}/cli/php.ini \
    -e "s/^memory_limit.*/memory_limit = ${PHP_MEMORY_LIMIT}/" /etc/php/${PHP_VERSION}/cli/php.ini \
    -e "s/^max_execution_time.*/max_execution_time = ${PHP_MAX_EXECUTION_TIME}/" /etc/php/${PHP_VERSION}/cli/php.ini

echo "Editing phpmyadmin config" && \
    sed -i "s/cfg\['blowfish_secret'\] = ''/cfg['blowfish_secret'] = '`openssl rand -hex 16`'/" /var/www/phpmyadmin/config.inc.php

# Check if phpMyAdmin is enabled
if [[ "$PHPMYADMIN_ENABLED" == "False" ]]; then
    echo "Disabling phpMyAdmin"
    sed -i "s|Alias /phpmyadmin /var/www/phpmyadmin|# phpmyadmin disabled|" /etc/apache2/sites-available/000-default.conf
else
    echo "Enabling phpMyAdmin"
fi
# create a .htacess file if not exists
if [ ! -f /app/.htaccess ]; then
    echo "Creating .htaccess file"
    {
        echo "# write your custom settings, uncomment or add your directives"
        echo "# php_value max_execution_time 600"
        echo "# php_value max_input_time 600"
        echo "# php_value memory_limit 512M" 
    } > /app/.htaccess
    # set the permissions
    chmod 644 /app/.htaccess
    echo "The .htaccess file has been created"
else
    echo "The .htaccess file already exists"
fi

echo "Editing Mysql config"
if [ -e /var/run/mysqld/mysqld.sock ];then
    echo "Removing MySQL socket"
    rm -f /var/run/mysqld/mysqld.sock
fi


if [[ ! -d /var/lib/mysql/mysql ]]; then
    echo "=> An empty or uninitialized MySQL volume is detected in /var/lib/mysql"
    echo "=> Installing or restoring MySQL ..."

    # Try the 'preferred' solution
    mariadb-install-db --user=mysql --auth-root-authentication-method=socket --skip-test-db 
    if [ $? -ne 0 ]; then
        # Fall back to the 'depreciated' solution
        mysql_install_db > /dev/null 2>&1
    fi

    echo "=> Done!"
    /mysql_init.sh
    # create the mysql settings
    #echo "=> Creating mysql settings"
    _user=${MYSQL_USER_NAME:?}
    _userdb=${MYSQL_USER_DB:?}
    _userpass=${MYSQL_USER_PASS:?}
    #su - www-data -s /bin/bash -c "/usr/bin/php /app/bin/console db:install --no-interaction --quiet --db-host=127.0.0.1 --db-port=3306 --db-name=${_userdb} --db-user=${_user} --db-password=${_userpass} --force --reconfigure"
    # populate the time zone tables
    echo "=> Populating the time zone tables"
    mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql  mysql

else
    echo "=> Using an existing volume of MySQL"
    #echo "Upgrading glpi database"
    #su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:maintenance:enable"
    #su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console db:update --allow-unstable --no-interaction"
    #su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:migration:myisam_to_innodb --no-interaction"
    #su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:migration:utf8mb4 --no-interaction"
    #su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:migration:unsigned_keys --no-interaction"
    #su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:maintenance:disable"
fi
echo "Starting supervisord"
exec supervisord -c /etc/supervisor/supervisord.conf -n
mysql -uroot -e "GRANT SELECT ON mysql.time_zone_name TO '${_user}'"
su - www-data -s /bin/bash -c "/usr/bin/php /app/bin/console database:enable_timezones"
su - www-data -s /bin/bash -c "/usr/bin/php /app/bin/console db:install --no-interaction --quiet --db-host=127.0.0.1 --db-port=3306 --db-name=${_userdb} --db-user=${_user} --db-password=${_userpass} --force --reconfigure"
echo "Upgrading glpi database"
su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:maintenance:enable"
su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console db:update --allow-unstable --no-interaction"
su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:migration:myisam_to_innodb --no-interaction"
su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:migration:utf8mb4 --no-interaction"
su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:migration:unsigned_keys --no-interaction"
su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:maintenance:disable"
