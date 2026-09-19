#!/bin/sh
set -eu
nc -z -w 1 127.0.0.1 22
nc -z -w 1 127.0.0.1 2222
nc -z -w 1 127.0.0.1 8080
test -S /run/php/php-fpm.sock
redis-cli -h 127.0.0.1 ping | grep -qx PONG
