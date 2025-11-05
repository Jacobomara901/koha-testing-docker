#!/bin/bash

set -e

echo "[SSO] Installing Shibboleth SP packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y shibboleth-sp-common libapache2-mod-shib

echo "[SSO] Copying Shibboleth configuration files"
for config_file in /sso_configs/*; do
    if [ -f "$config_file" ] && [ "$(basename $config_file)" != "sso.sh" ]; then
        cp "$config_file" /etc/shibboleth/
        echo "    [*] Copied $(basename $config_file)"
    fi
done

echo "[SSO] Configuring Apache for Shibboleth on OPAC"
APACHE_CONF="/etc/apache2/sites-enabled/kohadev.conf"

if ! grep -q "AuthType shibboleth" "$APACHE_CONF"; then
    sed -i '/<VirtualHost \*:8080>/,/<\/VirtualHost>/ {
        /<\/VirtualHost>/i\    <Location "/">\
    AuthType shibboleth\
    Require shibboleth\
    ShibUseEnvironment Off\
    ShibUseHeaders On\
    </Location>
    }' "$APACHE_CONF"
    echo "    [*] Added Shibboleth configuration to OPAC VirtualHost"
else
    echo "    [*] Shibboleth configuration already present"
fi

echo "[SSO] Restarting Apache"
service apache2 restart
service shibd restart

echo "[SSO] Shibboleth SP setup complete"
