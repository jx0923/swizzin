#!/bin/bash
codename=$(lsb_release -cs)
if [[ -f /tmp/.install.lock ]]; then
  log="/root/logs/install.log"
else
  log="/dev/null"
fi

if [[ $codename == "jessie" ]]; then
  geoip=php7.0-geoip
else
  geoip=php-geoip
fi


APT='php-fpm php-cli php-dev php-xml php-curl php-xmlrpc php-json php-mcrypt php-mbstring php-opcache '"${geoip}"' php-xml'
for depends in $APT; do
  inst=$(dpkg -l | grep $depends)
  if [[ -z $inst ]]; then
    last_update=$(stat -c %Y /var/cache/apt/pkgcache.bin)
    now=$(date +%s)
    if [ $((now - last_update)) -gt 3600 ]; then
      apt-get -y -qq update
    fi
    apt-get -y install "$depends" >> $log 2>&1
  fi
done

cd /etc/php
phpv=$(ls -d */ | cut -d/ -f1)
if [[ $phpv =~ "7.1" ]]; then
  if [[ $phpv =~ "7.0" ]]; then
    apt-get -y -q purge php7.0-fpm
  fi
fi

if [[ -f /lib/systemd/system/php7.1-fpm.service ]]; then
  sock=php7.1-fpm
else
  sock=php7.0-fpm
fi

for version in $phpv; do
  if [[ -f /etc/php/$version/fpm/php.ini ]]; then
    sed -i -e "s/post_max_size = 8M/post_max_size = 64M/" \
            -e "s/upload_max_filesize = 2M/upload_max_filesize = 92M/" \
            -e "s/expose_php = On/expose_php = Off/" \
            -e "s/128M/768M/" \
            -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" \
            -e "s/;opcache.enable=0/opcache.enable=1/" \
            -e "s/;opcache.memory_consumption=64/opcache.memory_consumption=128/" \
            -e "s/;opcache.max_accelerated_files=2000/opcache.max_accelerated_files=4000/" \
            -e "s/;opcache.revalidate_freq=2/opcache.revalidate_freq=240/" /etc/php/$version/fpm/php.ini
    phpenmod -v $version opcache
  fi
done

if [[ -f /lib/systemd/system/php7.1-fpm.service ]]; then
  oldv=$(find /etc/nginx -type f -exec grep -l "fastcgi_pass unix:/run/php/php7.0-fpm.sock" {} \;)
  if [[ -n $oldv ]]; then
    for upgrade in $oldv; do
      sed -i 's/fastcgi_pass unix:\/run\/php\/php7.0-fpm.sock/fastcgi_pass unix:\/run\/php\/php7.1-fpm.sock/g' $upgrade
    done
  fi
fi

if grep -q -e "-dark" -e "Nginx-Fancyindex" /srv/fancyindex/header.html; then
  sed -i 's/href="\/[^\/]*/href="\/fancyindex/g' /srv/fancyindex/header.html
fi

if grep -q "Nginx-Fancyindex" /srv/fancyindex/footer.html; then
  sed -i 's/src="\/[^\/]*/src="\/fancyindex/g' /srv/fancyindex/footer.html
fi

if [[ -f /lib/systemd/system/php7.1-fpm.service ]]; then
  systemctl restart php7.1-fpm
  if [[ $(systemctl is-active php7.0-fpm) == "active" ]]; then
    systemctl stop php7.0-fpm
    systemctl disable php7.0-fpm
  fi
else
  systemctl restart php7.0-fpm
fi
systemctl reload nginx