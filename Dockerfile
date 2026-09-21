FROM debian:bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpam0g-dev libssl-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY source/ ./
RUN make -j"$(nproc)" LIBS='-lpam -lcrypt' && test -x vsftpd

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libpam0g libssl3 netcat-openbsd inetutils-ftp sudo bsdutils openssh-server nginx-light redis-server php-fpm && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /usr/share/empty /srv/ftp /run/sshd /run/redis /run/php \
    && useradd --system --home-dir /srv/ftp --shell /usr/sbin/nologin ftp \
    && useradd --create-home --uid 1001 --user-group --shell /bin/bash vyshu \
    && useradd --create-home --uid 1002 --user-group --shell /bin/bash vyshu5678 \
    && unlink /usr/bin/ftp \
    && chown redis:redis /run/redis \
    && chmod 0555 /srv/ftp
COPY --from=build /src/vsftpd /usr/local/sbin/vsftpd
COPY vsftpd.conf /etc/vsftpd.conf
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
COPY sudoers-vyshu /etc/sudoers.d/vyshu
COPY sudoers-vyshu5678 /etc/sudoers.d/vyshu5678
COPY ftp-wrapper /usr/bin/ftp
COPY INS.txt /home/vyshu/INS.txt
COPY INS-web.txt /home/vyshu5678/INS.txt
COPY commander.txt /root/commander.txt
COPY commander-web.txt /root/freemedia/commander.txt
COPY sshd_config /etc/ssh/sshd_config
COPY redis.conf /etc/redis/redis.conf
COPY nginx.conf /etc/nginx/nginx.conf
COPY php-fpm-pool.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY decoy-index.html /var/www/html/index.html
COPY freemedia/ /var/www/html/freemedia/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
ARG PHP_CALLBACK_IP=192.168.56.12
RUN sed -i "s/192\\.168\\.56\\.12/${PHP_CALLBACK_IP}/" /var/www/html/freemedia/uploads/shell.php \
    && chmod 0755 /usr/local/bin/healthcheck.sh \
    && chmod 0755 /usr/local/bin/entrypoint.sh \
    && chmod 0755 /usr/bin/ftp \
    && chmod 0440 /etc/sudoers.d/vyshu \
    && chmod 0440 /etc/sudoers.d/vyshu5678 \
    && visudo -cf /etc/sudoers.d/vyshu \
    && visudo -cf /etc/sudoers.d/vyshu5678 \
    && chown vyshu:vyshu /home/vyshu/INS.txt \
    && chmod 0644 /home/vyshu/INS.txt \
    && chown vyshu5678:vyshu5678 /home/vyshu5678/INS.txt \
    && chmod 0644 /home/vyshu5678/INS.txt \
    && chown -R vyshu5678:vyshu5678 /var/www/html/freemedia/uploads \
    && chmod 0775 /var/www/html/freemedia/uploads \
    && chmod 0600 /root/commander.txt \
    && chmod 0600 /root/freemedia/commander.txt
EXPOSE 22 2222 8080 6200 6379
HEALTHCHECK --interval=15s --timeout=8s --start-period=10s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
