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

APACHE_CONF="/etc/apache2/sites-enabled/kohadev.conf"
echo "[SSO] Configuring Apache for Shibboleth on OPAC"

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
    echo "    [*] Shibboleth configuration for OPAC already present"
fi

echo "[SSO] Configuring Apache for Shibboleth on Intranet"

if ! grep -q "ShibRequestSetting applicationId kohadev-intra" "$APACHE_CONF"; then
    sed -i '/<VirtualHost \*:8081>/,/<\/VirtualHost>/ {
        /<\/VirtualHost>/i\    <Location "/">\
    ShibRequestSetting applicationId kohadev-intra\
    AuthType shibboleth\
    Require shibboleth\
    ShibUseEnvironment Off\
    ShibUseHeaders On\
    </Location>
    }' "$APACHE_CONF"
    echo "    [*] Added Shibboleth configuration to Intranet VirtualHost"
else
    echo "    [*] Shibboleth configuration for Intranet already present"
fi

echo "[SSO] Configuring Koha Shibboleth settings"
koha-mysql kohadev <<EOF
-- Enable Shibboleth authentication
UPDATE systempreferences SET value = '1' WHERE variable = 'ShibbolethAuthentication';

-- Set base URLs
UPDATE systempreferences SET value = 'http://localhost:8080' WHERE variable = 'OPACBaseURL';
UPDATE systempreferences SET value = 'http://localhost:8081' WHERE variable = 'staffClientBaseURL';

-- Configure Shibboleth autocreate
INSERT INTO shibboleth_config (autocreate, sync, welcome, force_opac_sso, force_staff_sso)
VALUES (1, 1, 0, 0, 0)
ON DUPLICATE KEY UPDATE autocreate = 1, sync = 1;

-- Add default field mappings
INSERT INTO shibboleth_field_mappings (idp_field, koha_field, is_matchpoint, default_content)
VALUES
    ('email', 'userid', 1, NULL),
    ('surname', 'surname', 0, NULL),
    ('givenName', 'firstname', 0, NULL),
    (NULL, 'branchcode', 0, 'CPL'),
    (NULL, 'categorycode', 0, 'S')
ON DUPLICATE KEY UPDATE
    idp_field = VALUES(idp_field),
    is_matchpoint = VALUES(is_matchpoint),
    default_content = VALUES(default_content);
EOF

echo "    [*] Shibboleth settings configured in Koha"

echo "[SSO] Restarting services"
service shibd restart
service apache2 restart
flush_memcached

echo "[SSO] Shibboleth SP setup complete"
