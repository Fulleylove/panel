# Add user in shell

USERNAME=$1
PRIMARYDOMAIN=$2

useradd --comment "Ollie Panel $USERNAME" -G homeusers --create-home --password "hello" --user-group $USERNAME
mkdir /home/$USERNAME/
mkdir /home/$USERNAME/logs/
mkdir /home/$USERNAME/logs/apache/
touch /home/$USERNAME/logs/apache/$PRIMARYDOMAIN.access.log
touch /home/$USERNAME/logs/apache/$PRIMARYDOMAIN.error.log
mkdir /home/$USERNAME/$PRIMARYDOMAIN/

cp /home/panel/nginx_proxy/default-nginx-entry.conf /home/panel/nginx_proxy/conf.d/sites-available/$USERNAME.conf
sed -i "s/primary_domain/$PRIMARYDOMAIN/g" /home/panel/nginx_proxy/conf.d/sites-available/$USERNAME.conf
sed -i "s/username/$USERNAME/g" /home/panel/nginx_proxy/conf.d/sites-available/$USERNAME.conf

cp /home/panel/nginx_proxy/default-httpd-configuration.conf /home/panel/apache/conf/conf.d/$USERNAME.conf

sed -i "s/username/$USERNAME/g" /home/panel/apache/conf/conf.d/$USERNAME.conf
sed -i "s/primary_domain/$PRIMARYDOMAIN/g" /home/panel/apache/conf/conf.d/$USERNAME.conf

chmod -R 777 /home/$USERNAME/

mkdir /home/panel/phpfpm/$USERNAME/

cp /home/panel/nginx_proxy/default-phpfpm-docker-compose.yaml /home/panel/phpfpm/$USERNAME/docker-compose.yaml

cd /home/panel/phpfpm/$USERNAME/

sed -i "s/username/$USERNAME/g" /home/panel/phpfpm/$USERNAME/docker-compose.yaml
sed -i "s/primary_domain/$PRIMARYDOMAIN/g" /home/panel/phpfpm/$USERNAME/docker-compose.yaml

docker-compose --file /home/panel/phpfpm/$USERNAME/docker-compose.yaml up --detach

docker network connect apache_network $USERNAME-phpfpm

docker exec -d nginx_proxy nginx -s reload
docker restart apache_container

docker update --memory=1g --memory-swap=2G  --cpus="1" --pids-limit=100 $USERNAME-phpfpm

echo "$USERNAME:password:$USERNAME-phpfpm" >> /home/panel/auth

docker restart ssh_container

mysqladmin --host=127.0.0.1 --user=root --password=password123 create $USERNAME\_database

docker exec -d mariadb_container mysql -u root -ppassword123 -e "CREATE USER '${USERNAME}_username'@'%' IDENTIFIED BY 'password456';"
docker exec -d mariadb_container mysql -u root -ppassword123 -e "FLUSH PRIVILEGES;"

mkdir /home/$USERNAME/mail
mkdir /home/$USERNAME/mail/$PRIMARYDOMAIN
chmod 777 -R /home/$USERNAME/mail/$PRIMARYDOMAIN

echo "a@$PRIMARYDOMAIN $USERNAME/mail/$PRIMARYDOMAIN/a" >> /etc/postfix/vmailbox
postmap /etc/postfix/vmailbox
postfix reload
