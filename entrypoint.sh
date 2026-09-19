#!/bin/sh
set -eu

mkdir -p /run/sshd /run/redis /run/php
chown redis:redis /run/redis
chown vyshu5678:vyshu5678 /run/php

/usr/sbin/sshd
/usr/sbin/php-fpm8.2 -F &
/usr/sbin/nginx
/usr/sbin/runuser -u redis -- /usr/bin/redis-server /etc/redis/redis.conf

while :; do
    /usr/local/sbin/vsftpd /etc/vsftpd.conf || true
    sleep 1
done
