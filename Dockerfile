FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV OTRS_DB_TYPE=mysql
ENV DB_SOCKET=/var/run/mysqld/mysqld.sock

# Install required packages including build tools
RUN apt-get update && apt-get install -y \
    apache2 \
    libapache2-mod-perl2 \
    perl \
    build-essential \
    gcc \
    make \
    libdbd-mysql-perl \
    libtimedate-perl \
    libnet-dns-perl \
    libnet-ldap-perl \
    libio-socket-ssl-perl \
    libpdf-api2-perl \
    libsoap-lite-perl \
    libtext-csv-xs-perl \
    libjson-xs-perl \
    libapache-dbi-perl \
    libxml-parser-perl \
    libxml-libxml-perl \
    libyaml-perl \
    libarchive-zip-perl \
    libcrypt-eksblowfish-perl \
    libclass-inspector-perl \
    libcgi-pm-perl \
    libdbi-perl \
    libdbix-connector-perl \
    libtemplate-perl \
    libmail-imapclient-perl \
    libauthen-sasl-perl \
    libtemplate-perl \
    libdatetime-perl \
    libnet-smtp-ssl-perl \
    libmail-imapclient-perl \
    libauthen-ntlm-perl \
    libdigest-md5-perl \
    libdatetime-format-mysql-perl \
    libdate-manip-perl \
    libio-socket-ssl-perl \
    libmoo-perl \
    libnamespace-autoclean-perl \
    libparams-util-perl \
    libsub-name-perl \
    libtemplate-perl \
    libtext-csv-xs-perl \
    cpanminus \
    wget \
    mysql-client \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install additional Perl modules via cpanm
RUN cpanm --notest \
    DateTime \
    DateTime::TimeZone \
    Mail::IMAPClient \
    Modern::Perl \
    JSON::XS \
    Encode::HanExtra \
    IO::Socket::SSL \
    Crypt::Eksblowfish::Bcrypt \
    XML::Parser::Lite \
    XML::LibXML::Simple \
    Moo \
    YAML \
    Apache::DBI \
    Template

# Download and install OTRS
RUN cd /tmp && \
    wget https://download.znuny.org/releases/otrs-6.0.30.tar.gz && \
    tar -xzf otrs-6.0.30.tar.gz && \
    mv otrs-6.0.30 /opt/otrs && \
    rm -f otrs-6.0.30.tar.gz

WORKDIR /opt/otrs

# Create OTRS user
RUN useradd -d /opt/otrs -c 'OTRS user' otrs && \
    usermod -G www-data otrs

# Set up basic configuration
RUN cp Kernel/Config.pm.dist Kernel/Config.pm && \
    mkdir -p var/cron && \
    cp scripts/apache2-httpd.include.conf /etc/apache2/conf-available/otrs.conf

# Create necessary directories and set permissions
RUN mkdir -p var/article var/spool var/tmp var/cron && \
    chown -R otrs:www-data . && \
    chmod -R 755 . && \
    for dir in var/article var/spool var/tmp var/cron; do \
        chmod 2775 $dir; \
    done

# Copy startup script
COPY docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
