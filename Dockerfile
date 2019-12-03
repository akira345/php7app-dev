FROM php:7.3-apache

# Setting locale
RUN apt-get update \
  && apt-get install -y locales \
  && rm -rf /var/lib/apt/lists/* \
  && echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen \
  && locale-gen ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8
ENV TZ "Asia/Tokyo"

# Setting Envionment
ENV DOCUMENT_ROOT /var/www/web/html
ENV MEMCACHED_HOST memcached_srv

# copy from custom bashrc
COPY .bashrc /root/

# install postgresql11 client
RUN apt-get update && apt-get install --no-install-recommends -y wget gnupg gnupg2 gnupg1 \
  && wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | apt-key add - \
  && sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" >> /etc/apt/sources.list.d/pgdg.list' \
  && apt-get update \
  && apt-get install --no-install-recommends -y postgresql-client-11

# install php middleware
RUN apt-get update && apt-get install --no-install-recommends -y \
  git curl unzip vim wget sudo libfreetype6-dev libjpeg62-turbo-dev libmcrypt-dev libmcrypt-dev libzip-dev \
  libxml2-dev libpq-dev libpq5 mariadb-client ssl-cert libicu-dev libmemcached-dev libgmp3-dev \
  && docker-php-ext-configure \
  gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
  && docker-php-ext-install -j$(nproc) \
  mbstring zip gd xml pdo pdo_pgsql pdo_mysql soap intl opcache pgsql mysqli gmp \
  && rm -r /var/lib/apt/lists/*

# install php pecl extentions
RUN pecl channel-update pecl.php.net \
  && pecl install memcached \
  && docker-php-ext-enable memcached

# copy from custom php.ini file
COPY php.ini /usr/local/etc/php/

# Install Python3.7 and more...
RUN apt-get update && apt-get install -y --no-install-recommends \
  tk-dev \
  uuid-dev \
  dirmngr \
  libffi-dev \
  libssl-dev \
  libncurses5-dev \
  libsqlite3-dev \
  libreadline-dev \
  libtk8.5 \
  libgdm-dev \
  libdb4o-cil-dev \
  libpcap-dev \
  && rm -rf /var/lib/apt/lists/*
ENV GPG_KEY 0D96DF4D4110E5C43FBFB17F2D347EA6AA65421D
ENV PYTHON_VERSION 3.7.3

RUN set -ex \
  \
  && wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" \
  && wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" \
  && export GNUPGHOME="$(mktemp -d)" \
  && gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
  && gpg --batch --verify python.tar.xz.asc python.tar.xz \
  && { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
  && rm -rf "$GNUPGHOME" python.tar.xz.asc \
  && mkdir -p /usr/src/python \
  && tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
  && rm python.tar.xz \
  \
  && cd /usr/src/python \
  && gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
  && ./configure \
  --build="$gnuArch" \
  --enable-loadable-sqlite-extensions \
  --enable-shared \
  --with-system-expat \
  --with-system-ffi \
  --without-ensurepip \
  --enable-optimizations \
  && make -j "$(nproc)" \
  && make install \
  && ldconfig \
  \
  && find /usr/local -depth \
  \( \
  \( -type d -a \( -name test -o -name tests \) \) \
  -o \
  \( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
  \) -exec rm -rf '{}' + \
  && rm -rf /usr/src/python \
  \
  && python3 --version

# make some useful symlinks that are expected to exist
RUN cd /usr/local/bin \
  && ln -s idle3 idle \
  && ln -s pydoc3 pydoc \
  && ln -s python3 python \
  && ln -s python3-config python-config

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 19.1.1

RUN set -ex; \
  \
  wget -O get-pip.py 'https://bootstrap.pypa.io/get-pip.py'; \
  \
  python get-pip.py \
  --disable-pip-version-check \
  --no-cache-dir \
  "pip==$PYTHON_PIP_VERSION" \
  ; \
  pip --version; \
  \
  find /usr/local -depth \
  \( \
  \( -type d -a \( -name test -o -name tests \) \) \
  -o \
  \( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
  \) -exec rm -rf '{}' +; \
  rm -f get-pip.py

RUN pip install boto3

# install adminer
RUN mkdir -p /var/www/adminer \
  && cd /var/www/adminer \
  && wget https://www.adminer.org/static/download/4.7.5/adminer-4.7.5.php \
  && wget https://raw.githubusercontent.com/vrana/adminer/master/designs/nicu/adminer.css \
  && mv adminer-4.7.5.php index.php

# install memached monitor
RUN mkdir -p /var/www/memcached \
  && cd /var/www/memcached \
  && wget https://raw.githubusercontent.com/DBezemer/memcachephp/master/memcache.php \
  && mv ./memcache.php ./index.php 

# setting apache virtualhost
COPY virtual.conf /etc/apache2/sites-available/
RUN mkdir -p /var/log/httpd/php7.localdomain \
  && mkdir -p /var/www/web \
  && ln -s /dev/stdout /var/log/httpd/php7.localdomain/access_log \
  && ln -s /dev/stderr /var/log/httpd/php7.localdomain/error_log \
  && a2enmod rewrite \
  && a2dissite 000-default \
  && a2ensite virtual \
  && service apache2 restart
RUN chown -R www-data: /var/www

# install composer and settings
RUN curl -sS https://getcomposer.org/installer | php -- \
  --filename=composer \
  --install-dir=/usr/local/bin

USER www-data
RUN composer global require --optimize-autoloader \
  "hirak/prestissimo"
# install laravel installer
RUN composer global require --optimize-autoloader \
  "laravel/installer"
USER root
WORKDIR /var/www/web
VOLUME /var/www/web

# Setting Document Root and start apache
COPY --chown=root:root endpoint_script.sh /tmp
RUN chmod +x /tmp/endpoint_script.sh
ENTRYPOINT ["/tmp/endpoint_script.sh"]
CMD [ "apache2-foreground" ]