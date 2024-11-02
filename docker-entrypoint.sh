#!/bin/bash
set -e

# Function for error handling
handle_error() {
    echo "Error occurred in script at line: ${1}"
    echo "Line exited with status: ${2}"
}

# Enable error handling
trap 'handle_error ${LINENO} $?' ERR

# Enable verbose logging
set -x

# Enable required Apache modules
a2enmod perl
a2enmod headers
a2enmod cgid
a2enmod deflate
a2enmod rewrite
a2enmod auth_basic
a2enmod authn_file

# Configure Apache
echo "Configuring Apache..."
cat > /etc/apache2/sites-available/otrs.conf << 'EOF'
<VirtualHost *:80>
    ServerName localhost
    ServerAdmin root@localhost
    DocumentRoot /opt/otrs/var/httpd/htdocs

    <Directory /opt/otrs/var/httpd/htdocs>
        AllowOverride None
        Require all granted
    </Directory>

    Alias /otrs-web "/opt/otrs/var/httpd/htdocs"
    ScriptAlias /otrs/ "/opt/otrs/bin/cgi-bin/"
    ScriptAlias /otrs "/opt/otrs/bin/cgi-bin/"

    <Directory "/opt/otrs/bin/cgi-bin/">
        AllowOverride None
        Options +ExecCGI
        Require all granted

        <IfModule mod_headers.c>
            Header always unset X-Frame-Options
        </IfModule>
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/otrs-error.log
    CustomLog ${APACHE_LOG_DIR}/otrs-access.log combined
</VirtualHost>
EOF

# Enable the OTRS site
a2ensite otrs
a2dissite 000-default

# Configure global Apache settings
echo "ServerName localhost" >> /etc/apache2/apache2.conf

echo "Waiting for database..."
maxTries=60
while [ $maxTries -gt 0 ]; do
    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1" &> /dev/null; then
        echo "Database is ready!"
        break
    fi
    maxTries=$((maxTries - 1))
    echo "Attempt $maxTries: Waiting for database..."
    sleep 2
done

if [ $maxTries -eq 0 ]; then
    echo "Could not connect to database after multiple attempts"
    exit 1
fi

# Configure OTRS
cd /opt/otrs

# Create necessary directories
echo "Creating directories..."
for dir in tmp var/tmp var/article var/spool var/cron var/log custom Kernel/Config/Files/Custom; do
    mkdir -p $dir
    chown -R otrs:www-data $dir
    chmod 2775 $dir
done

# Generate Config.pm
echo "Generating Config.pm..."
cat > Kernel/Config.pm << EOF
# Config file for OTRS
package Kernel::Config;
use strict;
use warnings;
use utf8;

sub Load {
    my \$Self = shift;

    # Database settings
    \$Self->{'DatabaseHost'} = '$DB_HOST';
    \$Self->{'Database'} = '$DB_NAME';
    \$Self->{'DatabaseUser'} = '$DB_USER';
    \$Self->{'DatabasePw'} = '$DB_PASS';
    \$Self->{'DatabasePort'} = '$DB_PORT';
    \$Self->{'DatabaseDSN'} = "DBI:mysql:database=\$Self->{'Database'};host=\$Self->{'DatabaseHost'};port=\$Self->{'DatabasePort'}";

    # System settings
    \$Self->{Home} = '/opt/otrs';
    \$Self->{SecureMode} = 1;
    \$Self->{SystemID} = '$OTRS_SYSTEM_ID';
    \$Self->{Organization} = '$ORGANIZATION';
    \$Self->{HttpType} = 'http';
    \$Self->{FQDN} = 'localhost';
    \$Self->{ScriptAlias} = 'otrs/';
    \$Self->{AdminEmail} = '$ADMIN_EMAIL';
    \$Self->{DefaultLanguage} = 'en';
    \$Self->{CheckEmailAddresses} = 0;
    \$Self->{CheckMXRecord} = 0;
    \$Self->{EnableNodeSupport} = 0;
    \$Self->{DefaultTheme} = 'Standard';

    return 1;
}

use vars qw(%ConfigHash);
\$ConfigHash{Version} = '1.0';
use base qw(Kernel::Config::Defaults);

1;
EOF

chown otrs:www-data Kernel/Config.pm
chmod 644 Kernel/Config.pm

# Initialize OTRS if not already initialized
if [ ! -f var/tmp/initialized ]; then
    echo "Initializing OTRS..."
    
    echo "Setting permissions..."
    bin/otrs.SetPermissions.pl --web-group=www-data

    echo "Installing database schema..."
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < scripts/database/otrs-schema.mysql.sql
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < scripts/database/otrs-initial_insert.mysql.sql
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < scripts/database/otrs-schema-post.mysql.sql

    echo "Setting up admin user..."
    HASHED_PW=$(perl -MDigest::MD5 -e "print Digest::MD5::md5_hex('$ADMIN_PASSWORD');")
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" << EOF
UPDATE users
SET login = 'root\@localhost',
    first_name = 'System',
    last_name = 'Administrator',
    valid_id = 1,
    pw = CONCAT('\$1\$', '$HASHED_PW')
WHERE id = 1;
EOF

    echo "Rebuilding configuration..."
    su -c "bin/otrs.Console.pl Maint::Config::Rebuild" -s /bin/bash otrs
    
    echo "Deploying configuration..."
    su -c "bin/otrs.Console.pl Admin::Config::Commit" -s /bin/bash otrs

    touch var/tmp/initialized
    chown otrs:www-data var/tmp/initialized
    echo "OTRS initialization complete"
fi

echo "Final permission setup..."
chown -R otrs:www-data .
chmod -R 755 .
find . -type f -name '*.sh' -exec chmod 755 {} \;
for dir in tmp var/tmp var/article var/spool var/cron var/log; do
    chmod 2775 $dir
done

echo "Starting OTRS daemon..."
su -c "bin/otrs.Daemon.pl start" -s /bin/bash otrs

echo "Testing Apache config..."
apache2ctl -t

echo "Starting Apache..."
rm -f /var/run/apache2/apache2.pid

echo "Starting services..."
/usr/sbin/apache2ctl -DFOREGROUND
