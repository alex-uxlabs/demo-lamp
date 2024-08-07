#!/bin/bash

set -eu

mkdir -p /app/data/public /run/apache2 /run/app/sessions /app/data/apache

# generate files if neither index.* or .htaccess
if [[ -z "$(ls -A /app/data/public)" ]]; then
    echo "==> Generate files on first run" # possibly not first run if user deleted index.*
    cp /app/code/index.php /app/data/public/index.php
    echo -e "#!/bin/bash\n\n# Place custom startup commands here" > /app/data/run.sh
    touch /app/data/public/.htaccess
else
    echo "==> Do not override existing index file"
fi

if [[ ! -f /app/data/php.ini ]]; then
    echo -e "; Add custom PHP configuration in this file\n; Settings here are merged with the package's built-in php.ini; Restart the app for any changes to take effect\n\n" > /app/data/php.ini
fi

[[ ! -f /app/data/apache/mpm_prefork.conf ]] && cp /app/code/apache/mpm_prefork.conf /app/data/apache/mpm_prefork.conf
[[ ! -f /app/data/apache/app.conf ]] && cp /app/code/apache/app.conf /app/data/apache/app.conf
[[ ! -f /app/data/PHP_VERSION ]] && echo -e "; Set the desired PHP version in this file\n; Restart app for changes to take effect\nPHP_VERSION=8.3" > /app/data/PHP_VERSION

readonly php_version=$(sed -ne 's/^PHP_VERSION=\(.*\)$/\1/p' /app/data/PHP_VERSION)
echo "==> PHP version set to ${php_version}"
ln -sf /etc/apache2/mods-available/php${php_version}.conf /run/apache2/php.conf
ln -sf /etc/apache2/mods-available/php${php_version}.load /run/apache2/php.load

# source it so that env vars are persisted
echo "==> Source custom startup script"
[[ -f /app/data/run.sh ]] && source /app/data/run.sh

echo "==> Creating credentials.txt"
sed -e "s,\bMONGODB_HOST\b,${CLOUDRON_MONGODB_HOST}," \
    -e "s,\bMONGODB_PORT\b,${CLOUDRON_MONGODB_PORT}," \
    -e "s,\bMONGODB_USERNAME\b,${CLOUDRON_MONGODB_USERNAME}," \
    -e "s,\bMONGODB_PASSWORD\b,${CLOUDRON_MONGODB_PASSWORD}," \
    -e "s,\bMONGODB_DATABASE\b,${CLOUDRON_MONGODB_DATABASE}," \
    -e "s,\bMONGODB_URL\b,${CLOUDRON_MONGODB_URL}," \
    /app/code/credentials.template > /app/data/credentials.txt

chown -R www-data:www-data /app/data /run/apache2 /run/app /tmp

echo "==> Starting Lamp stack"
APACHE_CONFDIR="" source /etc/apache2/envvars
rm -f "${APACHE_PID_FILE}"
exec /usr/sbin/apache2 -DFOREGROUND

