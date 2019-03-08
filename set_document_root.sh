#! /bin/sh
set -e
sed -i -e "s#/var/www/web/html#${DOCUMENT_ROOT}#g" /etc/apache2/sites-available/virtual.conf 

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- apache2-foreground "$@"
fi

exec "$@"
