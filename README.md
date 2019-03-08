# php7app-dev
Container for PHP 7 Web application development

This container develops PHP 7 web application in the Japanese locale and time.

* Environments
	* DOCUMENT_ROOT  
	Sets the path of the document root in the container.(ex: /var/www/web/public_html)  
	Defailt path is /var/www/web/html

	* MEMCACHED_HOST  
		Set Memcached server name.  
		Defaiult name is memcached_srv.

* MountPoints
	* /var/www/web is Application Directroy into container.

* Preinstalled applications.
	* Adminer 4.7.1 into /adminer.
	* memcachephp into /memcached  
	(ID:memcache PW:password)
	* larabel installer and composer.
	* enable opcache.

* Commandline example.

	```docker run --rm -v `pwd`/app:/var/www/web -p 8080:80 -e DOCUMENT_ROOT=/var/www/web/public_html --name example akira345/php7app-dev```