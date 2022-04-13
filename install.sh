#!/bin/bash
docker
# docker build -t docker-ssh github.com/maxivak/docker-ssh

groupadd homeusers

cd /home/
rm -rf panel
docker rm --force $(docker ps -q)
docker container prune --force


docker network create apache_network


mkdir /home/panel

mkdir /home/panel/nginx_proxy/
mkdir /home/panel/nginx_proxy/conf.d
mkdir /home/panel/nginx_proxy/conf.d/sites-available/
mkdir /home/panel/nginx_proxy/conf.d/sites-enabled/

mkdir /home/panel/apache/
mkdir /home/panel/apache/conf.d
mkdir /home/panel/apache/conf.d/sites-available/
mkdir /home/panel/apache/conf.d/sites-enabled/


cat > /home/panel/nginx_proxy/conf.d/sites-available/fallback.conf << ENTRY
server{
    listen 80 default_server;
    location / {
    	proxy_set_header X-Real-IP \$remote_addr;
	    proxy_set_header X-Forwarded-For \$remote_addr;
	    proxy_set_header Host \$host;
        proxy_pass http://default_container:1000;
    }
}
server{
    listen 2087 default_server;
    location / {
    	proxy_set_header X-Real-IP \$remote_addr;
	    proxy_set_header X-Forwarded-For \$remote_addr;
	    proxy_set_header Host \$host;
        proxy_pass http://interface_container:2000;
    }
}

server{
    listen 80;
    server_name phpmyadmin.localhost;
    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host;
        proxy_pass http://phpmyadmin_container:80;
    }
}


ENTRY




cat > /home/panel/nginx_proxy/default-nginx-entry.conf << ENTRY
upstream username{
    server apache_container:8080;
}

server{
    listen 80;
    server_name primary_domain;
    location / {
    	proxy_set_header X-Real-IP \$remote_addr;
	    proxy_set_header X-Forwarded-For \$remote_addr;
	    proxy_set_header Host \$host;
        proxy_pass http://apache_container:8080;
    }

}

server{
    listen 80;
    server_name phpmyadmin.primary_domain;
    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host;
        proxy_pass http://phpmyadmin_container:80;
    }
}

server{
    listen 2087;
    server_name primary_domain;
    location / {
    	proxy_set_header X-Real-IP \$remote_addr;
	    proxy_set_header X-Forwarded-For \$remote_addr;
	    proxy_set_header Host \$host;
        proxy_pass http://interface_container:2000;
    }
}

ENTRY

cat > /home/panel/nginx_proxy/default-phpfpm-docker-compose.yaml << ENTRY
version: '3.1'
services:
  phpfpm:
    container_name: username-phpfpm
    image: 'bitnami/php-fpm:latest'
    volumes:
      - /home/username/:/home/username/
ENTRY

cat > /home/panel/nginx_proxy/default-httpd-configuration.conf << ENTRY
<Directory /var/www/html/username/primary_domain>
    Require all granted
</Directory>

<VirtualHost *:8080>
    DocumentRoot "/var/www/html/username/primary_domain"
    ServerName www.primary_domain
    ServerAlias primary_domain
    ServerAdmin username@primary_domain
    ErrorLog "/var/www/html/username/logs/apache/primary_domain.error.log"
    CustomLog "/var/www/html/username/logs/apache/primary_domain.access.log" combined
    ProxyPassMatch ^/(.*\.php(/.*)?)$ fcgi://username-phpfpm:9000/home/username/primary_domain/\$1
</VirtualHost>
ENTRY

mkdir /home/panel/apache/
mkdir /home/panel/apache/conf
mkdir /home/panel/apache/conf/conf.d/

cat > /home/panel/nginx_proxy/conf.d/default.conf << ENTRY
server {
    listen       80;
    listen  [::]:80;
    server_name  localhost;
    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }
}

ENTRY


mkdir /home/panel/phpfpm/

docker run --name nginx_proxy -p 80:80 -p 2087:2087 --mount type=bind,source=/home/panel/nginx_proxy/conf.d/,target=/etc/nginx/conf.d/ -d  nginx

sed -i 's#/etc/nginx/conf.d/\*.conf#/etc/nginx/conf.d/sites-available/*.conf#g' /etc/nginx/nginx.conf
docker network connect apache_network nginx_proxy
docker exec -d nginx_proxy sed -i 's#/etc/nginx/conf.d/\*.conf#/etc/nginx/conf.d/sites-available/*.conf#g' /etc/nginx/nginx.conf
docker exec -d nginx_proxy rm /etc/nginx/conf.d/default.conf

docker run --name apache_container -p 8080:8080 -p 443:8443 -d --mount type=bind,source=/home/,target=/var/www/html/ --mount type=bind,source=/home/panel/apache/conf/conf.d/,target=/opt/bitnami/apache2/conf/vhosts/ bitnami/apache:latest
docker network connect apache_network apache_container
docker restart apache_container

docker run --name default_container -p 1000:1000 -d --mount type=bind,source=/home/panel/,target=/var/www/html/ bitnami/apache:latest
docker network connect apache_network default_container
docker restart default_container

docker run --name interface_container -p 2000:2000 -d --mount type=bind,source=/home/panel/,target=/var/www/html/ bitnami/apache:latest
docker network connect apache_network interface_container
docker restart interface_container

docker exec -d nginx_proxy nginx -s reload

touch /home/panel/auth

chmod 777 /home/panel/auth

docker run -d --name ssh_container  -p 2222:22 -v /var/run/docker.sock:/var/run/docker.sock -e AUTH_MECHANISM=multiContainerAuth -e AUTH_TUPLES_FILE="/auth" -v /home/panel/auth:/auth docker-ssh
docker run -d --name mariadb_container --network apache_network --env MARIADB_ROOT_PASSWORD=password123 -p 3306:3306 mariadb:latest
docker run -d --name phpmyadmin_container --network apache_network --env PMA_HOST=mariadb_container -p 333:80 phpmyadmin

apt purge -y postfix

cd /home/ollie/Desktop/panel

wget https://raw.githubusercontent.com/docker-mailserver/docker-mailserver/master/setup.sh
chmod a+x ./setup.sh

docker pull docker.io/mailserver/docker-mailserver:latest

cat > docker-compose.yaml << ENTRY
version: '3.8'
services:
  mailserver:
    image: docker.io/mailserver/docker-mailserver:latest
    container_name: mail_container
    hostname: mail
    domainname: localhost
    ports:
      - "25:25"
      - "587:587"
      - "465:465"
    volumes:
      - ./docker-data/dms/mail-data/:/var/mail/
      - ./docker-data/dms/mail-state/:/var/mail-state/
      - ./docker-data/dms/mail-logs/:/var/log/mail/
      - ./docker-data/dms/config/:/tmp/docker-mailserver/
      - ./docker-data/nginx-proxy/certs/:/etc/letsencrypt/
      - /etc/localtime:/etc/localtime:ro
    environment:
      - ENABLE_FAIL2BAN=1
      - SSL_TYPE=letsencrypt
      - PERMIT_DOCKER=network
      - ONE_DIR=1
      - ENABLE_POSTGREY=0
      - ENABLE_CLAMAV=0
      - ENABLE_SPAMASSASSIN=0
      - SPOOF_PROTECTION=0
    cap_add:
      - SYS_PTRACE
ENTRY

docker-compose up

docker run --name roundcube_container -e ROUNDCUBEMAIL_DEFAULT_HOST=mail_container -e ROUNDCUBEMAIL_SMTP_SERVER=mail_container -p 8000:80 -d roundcube/roundcubemail

docker network connect apache_network roundcube_container
docker network connect apache_network mail_container

# ./setup.sh 

