#!/bin/bash

# # Wait for MySQL to be ready
# echo "Waiting for MySQL to start..."
# while ! mysqladmin ping -h localhost --silent; do
#     sleep 2
# done
# echo "MySQL is up."

# # Wait for Apache to be ready
# echo "Waiting for Apache to start..."
# while ! curl -s http://localhost > /dev/null; do
#     sleep 2
# done
# echo "Apache is up."

# Proceed with GLPI configuration
echo "Starting GLPI configuration..."

if -f /var/www/glpi/install/install.php; then
    echo "GLPI installation script found. Proceeding with installation..."
    # Run the GLPI installation script
    _user=${MYSQL_USER_NAME:?}
    _userdb=${MYSQL_USER_DB:?}
    _userpass=${MYSQL_USER_PASS:?}
    su - www-data -s /bin/bash -c "/usr/bin/php /app/bin/console db:install --no-interaction --quiet --db-host=127.0.0.1 --db-port=3306 --db-name=${_userdb} --db-user=${_user} --db-password=${_userpass} --force --reconfigure"
    # populate the time zone tables
    echo "=> Populating the time zone tables"
    mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql  mysql
    mysql -uroot -e "GRANT SELECT ON mysql.time_zone_name TO 'glpi'"
    echo "=> remove install.php"
    rm -rf /var/www/glpi/install/install.php
else
    echo "GLPI installation script not found. upgrading installation."
    su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:maintenance:enable"
    su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console db:update --allow-unstable --no-interaction"
    su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:migration:myisam_to_innodb --no-interaction"
    su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:migration:utf8mb4 --no-interaction"
    su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:migration:unsigned_keys --no-interaction"
    su - www-data -s /bin/bash -c "/usr/bin/php  /app/bin/console glpi:maintenance:disable"
fi
