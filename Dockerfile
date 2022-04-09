FROM php:7.4-apache

# Setting locale
RUN apt-get update \
  && apt-get install -y apt-utils locales fonts-ipafont libnss3 libx11-6 libnss3-dev libasound2-data  libasound2 xdg-utils chromium \
  && rm -rf /var/lib/apt/lists/* \
  && echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen \
  && locale-gen ja_JP.UTF-8
ENV LC_ALL ja_JP.UTF-8
ENV TZ "Asia/Tokyo"
ENV DEBIAN_FRONTEND noninteractive

# Setting Envionment
ENV DOCUMENT_ROOT /var/www/web/html
ENV MEMCACHED_HOST memcached_srv

# Build Environment
ENV ADMINER_VERSION 4.8.1
ENV NODE_VERSION 16.14.2
ENV YARN_VERSION 1.22.18

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 21.2.4
# https://github.com/docker-library/python/issues/365
ENV PYTHON_SETUPTOOLS_VERSION 58.1.0
# https://github.com/pypa/get-pip
ENV PYTHON_GET_PIP_URL https://github.com/pypa/get-pip/raw/38e54e5de07c66e875c11a1ebbdb938854625dd8/public/get-pip.py
ENV PYTHON_GET_PIP_SHA256 e235c437e5c7d7524fbce3880ca39b917a73dc565e0c813465b7a7a329bb279a

ENV GPG_KEY A035C8C19219BA821ECEA86B64E628F8D684696D
ENV PYTHON_VERSION 3.10.2

# copy from custom bashrc
COPY .bashrc /root/

# install postgresql12 client
RUN apt-get update && apt-get install --no-install-recommends -y wget gnupg gnupg2 gnupg1 \
  && wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | apt-key add - \
  && sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main" >> /etc/apt/sources.list.d/pgdg.list' \
  && apt-get update \
  && apt-get install --no-install-recommends -y postgresql-client-12

# install php middleware
RUN apt-get update && apt-get install --no-install-recommends -y \
  git curl unzip vim wget sudo libfreetype6-dev libjpeg62-turbo-dev libmcrypt-dev libmcrypt-dev libzip-dev \
  libxml2-dev libpq-dev libpq5 mariadb-client ssl-cert libicu-dev libmemcached-dev libgmp3-dev libonig-dev\
  && docker-php-ext-configure \
  gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/ \
  && docker-php-ext-install -j$(nproc) \
  mbstring zip gd xml pdo pdo_pgsql pdo_mysql soap intl opcache pgsql mysqli gmp\
  && rm -r /var/lib/apt/lists/*

# install php pecl extentions
RUN pecl channel-update pecl.php.net \
  && pecl install memcached \
  && docker-php-ext-enable memcached

# copy from custom php.ini file
COPY php.ini /usr/local/etc/php/

# Install Python3.10 and more...(based on debian:bullseye-slim)
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		netbase \
		tzdata \
	; \
	rm -rf /var/lib/apt/lists/*

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		dpkg-dev \
		gcc \
		gnupg dirmngr \
		libbluetooth-dev \
		libbz2-dev \
		libc6-dev \
		libexpat1-dev \
		libffi-dev \
		libgdbm-dev \
		liblzma-dev \
		libncursesw5-dev \
		libreadline-dev \
		libsqlite3-dev \
		libssl-dev \
		make \
		tk-dev \
		uuid-dev \
		wget \
		xz-utils \
		zlib1g-dev \
	; \
	\
	wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz"; \
	wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc"; \
	GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$GPG_KEY"; \
	gpg --batch --verify python.tar.xz.asc python.tar.xz; \
	command -v gpgconf > /dev/null && gpgconf --kill all || :; \
	rm -rf "$GNUPGHOME" python.tar.xz.asc; \
	mkdir -p /usr/src/python; \
	tar --extract --directory /usr/src/python --strip-components=1 --file python.tar.xz; \
	rm python.tar.xz; \
	\
	cd /usr/src/python; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	./configure \
		--build="$gnuArch" \
		--enable-loadable-sqlite-extensions \
		--enable-optimizations \
		--enable-option-checking=fatal \
		--enable-shared \
		--with-lto \
		--with-system-expat \
		--with-system-ffi \
		--without-ensurepip \
	; \
	nproc="$(nproc)"; \
	make -j "$nproc" \
		LDFLAGS="-Wl,--strip-all" \
	; \
	make install; \
	\
	cd /; \
	rm -rf /usr/src/python; \
	\
	find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests -o -name idle_test \) \) \
			-o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' -o -name '*.a' \) \) \
		\) -exec rm -rf '{}' + \
	; \
	\
	ldconfig; \
	\
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -not \( -name '*tkinter*' \) -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	python3 --version

# make some useful symlinks that are expected to exist ("/usr/local/bin/python" and friends)
RUN set -eux; \
	for src in idle3 pydoc3 python3 python3-config; do \
		dst="$(echo "$src" | tr -d 3)"; \
		[ -s "/usr/local/bin/$src" ]; \
		[ ! -e "/usr/local/bin/$dst" ]; \
		ln -svT "/usr/local/bin/$src" "/usr/local/bin/$dst"; \
	done

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends wget; \
	\
	wget -O get-pip.py "$PYTHON_GET_PIP_URL"; \
	echo "$PYTHON_GET_PIP_SHA256 *get-pip.py" | sha256sum -c -; \
	\
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	\
	export PYTHONDONTWRITEBYTECODE=1; \
	\
	python get-pip.py \
		--disable-pip-version-check \
		--no-cache-dir \
		--no-compile \
		"pip==$PYTHON_PIP_VERSION" \
		"setuptools==$PYTHON_SETUPTOOLS_VERSION" \
	; \
	rm -f get-pip.py; \
	\
	pip --version

RUN pip install boto3

# install adminer
RUN mkdir -p /var/www/adminer \
  && cd /var/www/adminer \
  && wget https://www.adminer.org/static/download/$ADMINER_VERSION/adminer-$ADMINER_VERSION.php \
  && wget https://raw.githubusercontent.com/vrana/adminer/master/designs/nicu/adminer.css \
  && mv adminer-$ADMINER_VERSION.php index.php

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
  #  && a2ensite virtual \
  && service apache2 restart
RUN chown -R www-data: /var/www

# install composer and settings
RUN curl -sS https://getcomposer.org/installer | php -- \
  --filename=composer \
  --install-dir=/usr/local/bin

USER www-data

# install laravel installer
RUN composer global require --optimize-autoloader \
  "laravel/installer"
USER root
WORKDIR /var/www/web
VOLUME /var/www/web

# install nodeJS(based on bullseye-slim)
RUN groupadd --gid 1000 node \
  && useradd --uid 1000 --gid node --shell /bin/bash --create-home node

RUN ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
      amd64) ARCH='x64';; \
      ppc64el) ARCH='ppc64le';; \
      s390x) ARCH='s390x';; \
      arm64) ARCH='arm64';; \
      armhf) ARCH='armv7l';; \
      i386) ARCH='x86';; \
      *) echo "unsupported architecture"; exit 1 ;; \
    esac \
    && set -ex \
    # libatomic1 for arm
    && apt-get update && apt-get install -y ca-certificates curl wget gnupg dirmngr xz-utils libatomic1 --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && for key in \
      4ED778F539E3634C779C87C6D7062848A1AB005C \
      141F07595B7B3FFE74309A937405533BE57C7D57 \
      94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
      74F12602B6F1C4E913FAA37AD3A89613643B6201 \
      71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
      8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
      C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
      C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
      DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
      A48C2BEE680E841632CD4E44F07496B3EB3C1762 \
      108F52B48DB57BB0CC439B2997B01419BD92F80A \
      B9E2F5981AA6E0CD28160D9FF13993A75599653C \
    ; do \
      gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
      gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
    done \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
    && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
    && grep " node-v$NODE_VERSION-linux-$ARCH.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
    && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt \
    && apt-mark auto '.*' > /dev/null \
    && find /usr/local -type f -executable -exec ldd '{}' ';' \
      | awk '/=>/ { print $(NF-1) }' \
      | sort -u \
      | xargs -r dpkg-query --search \
      | cut -d: -f1 \
      | sort -u \
      | xargs -r apt-mark manual \
#    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && ln -s /usr/local/bin/node /usr/local/bin/nodejs \
    # smoke tests
    && node --version \
    && npm --version

# install yarn
RUN set -ex \
  && savedAptMark="$(apt-mark showmanual)" \
  && apt-get update && apt-get install -y ca-certificates curl wget gnupg dirmngr --no-install-recommends \
  && rm -rf /var/lib/apt/lists/* \
  && for key in \
    6A010C5166006599AA17F08146C2130DFD2497F5 \
  ; do \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
  done \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
  && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && mkdir -p /opt \
  && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/ \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarn /usr/local/bin/yarn \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarnpkg /usr/local/bin/yarnpkg \
  && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && apt-mark auto '.*' > /dev/null \
  && { [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; } \
  && find /usr/local -type f -executable -exec ldd '{}' ';' \
    | awk '/=>/ { print $(NF-1) }' \
    | sort -u \
    | xargs -r dpkg-query --search \
    | cut -d: -f1 \
    | sort -u \
    | xargs -r apt-mark manual \
#  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
  # smoke test
  && yarn --version


# Setting Document Root and start apache
COPY --chown=root:root endpoint_script.sh /tmp
COPY --chown=root:root generate_certs.sh /tmp
RUN chmod +x /tmp/endpoint_script.sh
RUN chmod +x /tmp/generate_certs.sh
ENTRYPOINT ["/tmp/endpoint_script.sh"]
CMD [ "apache2-foreground" ]
