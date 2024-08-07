FROM cloudron/base:4.2.0@sha256:46da2fffb36353ef714f97ae8e962bd2c212ca091108d768ba473078319a47f4

RUN mkdir -p /app/code
WORKDIR /app/code

# when external repo is added, apt-get will install the latest in case of conflicting name. apt-cache policy <name> will show what is getting used
# so the remove of 7.4 is probably superfluous but here for completeness
# https://www.php.net/supported-versions.php
RUN apt-get remove -y php-* php7.4-* libapache2-mod-php7.4 && \
    apt-get autoremove -y && \
    add-apt-repository --yes ppa:ondrej/php && \
    apt update && \
    apt install -y php8.1 php8.1-{apcu,bcmath,bz2,cgi,cli,common,curl,dba,dev,enchant,fpm,gd,gmp,gnupg,imagick,imap,interbase,intl,ldap,mailparse,mbstring,mysql,odbc,opcache,pgsql,phpdbg,pspell,readline,redis,snmp,soap,sqlite3,sybase,tidy,uuid,xml,xmlrpc,xsl,zip,zmq} libapache2-mod-php8.1 && \
    apt install -y php-{date,pear,twig,validate} && \
    rm -rf /var/cache/apt /var/lib/apt/lists

# https://getcomposer.org/download/
RUN curl --fail -L https://getcomposer.org/download/2.7.7/composer.phar -o /usr/bin/composer && chmod +x /usr/bin/composer

# configure apache
# keep the prefork linking below a2enmod since it removes dangling mods-enabled (!)
# perl kills setlocale() in php - https://bugs.mageia.org/show_bug.cgi?id=25411
RUN a2disconf other-vhosts-access-log && \
    echo "Listen 80" > /etc/apache2/ports.conf && \
    a2enmod alias rewrite headers rewrite expires cache ldap authnz_ldap proxy proxy_http proxy_wstunnel && \
    a2dismod perl && \
    rm /etc/apache2/sites-enabled/* && \
    sed -e 's,^ErrorLog.*,ErrorLog "|/bin/cat",' -i /etc/apache2/apache2.conf && \
    ln -sf /app/data/apache/mpm_prefork.conf /etc/apache2/mods-enabled/mpm_prefork.conf && \
    ln -sf /app/data/apache/app.conf /etc/apache2/sites-enabled/app.conf && \
    rm /etc/apache2/mods-enabled/php*.conf /etc/apache2/mods-enabled/php*.load && \
    ln -sf /run/apache2/php.conf /etc/apache2/mods-enabled/php.conf && \
    ln -sf /run/apache2/php.load /etc/apache2/mods-enabled/php.load

COPY apache/ /app/code/apache/

# configure mod_php
RUN for v in 8.1; do \
        crudini --set /etc/php/$v/apache2/php.ini PHP upload_max_filesize 64M && \
        crudini --set /etc/php/$v/apache2/php.ini PHP post_max_size 64M && \
        crudini --set /etc/php/$v/apache2/php.ini PHP memory_limit 128M && \
        crudini --set /etc/php/$v/apache2/php.ini opcache opcache.enable 1 && \
        crudini --set /etc/php/$v/apache2/php.ini opcache opcache.enable_cli 1 && \
        crudini --set /etc/php/$v/apache2/php.ini opcache opcache.interned_strings_buffer 8 && \
        crudini --set /etc/php/$v/apache2/php.ini opcache opcache.max_accelerated_files 10000 && \
        crudini --set /etc/php/$v/apache2/php.ini opcache opcache.memory_consumption 128 && \
        crudini --set /etc/php/$v/apache2/php.ini opcache opcache.save_comments 1 && \
        crudini --set /etc/php/$v/apache2/php.ini opcache opcache.validate_timestamps 1 && \
        crudini --set /etc/php/$v/apache2/php.ini opcache opcache.revalidate_freq 60 && \
        crudini --set /etc/php/$v/apache2/php.ini Session session.save_path /run/app/sessions && \
        crudini --set /etc/php/$v/apache2/php.ini Session session.gc_probability 1 && \
        crudini --set /etc/php/$v/apache2/php.ini Session session.gc_divisor 100 ; \
    done

RUN for v in 8.1; do \
        cp /etc/php/$v/apache2/php.ini /etc/php/$v/cli/php.ini && \
        ln -s /app/data/php.ini /etc/php/$v/apache2/conf.d/99-cloudron.ini && \
        ln -s /app/data/php.ini /etc/php/$v/cli/conf.d/99-cloudron.ini ; \
    done

# install RPAF module to override HTTPS, SERVER_PORT, HTTP_HOST based on reverse proxy headers
# https://www.digitalocean.com/community/tutorials/how-to-configure-nginx-as-a-web-server-and-reverse-proxy-for-apache-on-one-ubuntu-16-04-server
RUN mkdir /app/code/rpaf && \
    curl -L https://github.com/gnif/mod_rpaf/tarball/669c3d2ba72228134ae5832c8cf908d11ecdd770 | tar -C /app/code/rpaf -xz --strip-components 1 -f -  && \
    cd /app/code/rpaf && \
    make && \
    make install && \
    rm -rf /app/code/rpaf

# configure rpaf
RUN echo "LoadModule rpaf_module /usr/lib/apache2/modules/mod_rpaf.so" > /etc/apache2/mods-available/rpaf.load && a2enmod rpaf

# ioncube. the extension dir comes from php -i | grep extension_dir
# extension has to appear first, otherwise will error with "The Loader must appear as the first entry in the php.ini file"
# ioncube does not seem to have support for PHP 8 yet (https://blog.ioncube.com/2022/08/12/ioncube-php-8-1-support-faq-were-almost-ready/)
# the dates below correspond to PHP build dates - https://unix.stackexchange.com/questions/591769/what-do-the-dates-at-usr-lib-php-represent
RUN mkdir /tmp/ioncube && \
    curl http://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz | tar zxvf - -C /tmp/ioncube && \
    cp /tmp/ioncube/ioncube/ioncube_loader_lin_8.1.so /usr/lib/php/20210902/ && \
    rm -rf /tmp/ioncube && \
    echo "zend_extension=/usr/lib/php/20210902/ioncube_loader_lin_8.1.so" > /etc/php/8.1/apache2/conf.d/00-ioncube.ini && \
    echo "zend_extension=/usr/lib/php/20210902/ioncube_loader_lin_8.1.so" > /etc/php/8.1/cli/conf.d/00-ioncube.ini

# add code
COPY start.sh index.php credentials.template python_requirements.txt /app/code/

# install python libraries
RUN python3 -m pip install -r python_requirements.txt

# lock www-data but allow su - www-data to work
RUN passwd -l www-data && usermod --shell /bin/bash --home /app/data www-data

CMD [ "/app/code/start.sh" ]
