ARG NGINX_VERSION=1.30.7
ARG ALPINE_VERSION=3.24
ARG NGINX_RTMP_MODULE_VERSION=1.2.2

FROM alpine:${ALPINE_VERSION} AS builder

ARG NGINX_VERSION
ARG NGINX_RTMP_MODULE_VERSION

RUN apk add --no-cache \
        ca-certificates \
        gcc \
        libc-dev \
        make \
        openssl-dev \
        pcre2-dev \
        zlib-dev \
        wget \
        tar

RUN wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O /tmp/nginx.tar.gz \
    && echo "2565b5c837050e958f70fb0f73c48e2bca4542ad349fd356f46fb0c72610bc6e  /tmp/nginx.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/nginx.tar.gz -C /tmp

RUN wget -q "https://github.com/arut/nginx-rtmp-module/archive/refs/tags/v${NGINX_RTMP_MODULE_VERSION}.tar.gz" -O /tmp/rtmp.tar.gz \
    && echo "07f19b7bffec5e357bb8820c63e5281debd45f5a2e6d46b1636d9202c3e09d78  /tmp/rtmp.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/rtmp.tar.gz -C /tmp \
    && mv /tmp/nginx-rtmp-module-* /tmp/nginx-rtmp-module

RUN cd "/tmp/nginx-${NGINX_VERSION}" \
    && ./configure \
        --with-compat \
        --add-dynamic-module=../nginx-rtmp-module \
    && make -j2 modules

FROM nginx:${NGINX_VERSION}-alpine${ALPINE_VERSION}

ARG NGINX_VERSION

COPY --from=builder "/tmp/nginx-${NGINX_VERSION}/objs/ngx_rtmp_module.so" /etc/nginx/modules/

RUN apk add --no-cache \
        ffmpeg \
        openssl \
        wget \
    && mkdir -p /www /var/rec /tmp/live \
    && chown nginx:nginx /var/rec /tmp/live \
    && printf '%s\n' \
        'location ^~ /control/ {' \
        '    return 404;' \
        '}' \
        '' \
        'location = /stat {' \
        '    allow 127.0.0.1;' \
        '    allow ::1;' \
        '    deny all;' \
        '    default_type text/xml;' \
        '    rtmp_stat all;' \
        '}' > /etc/nginx/control.conf \
    && printf '%s\n' 'record_path /var/rec;' > /etc/nginx/record-path.conf \
    && printf '%s\n' \
        'location = /internal/publish-check {' \
        '    default_type text/plain;' \
        '    access_log off;' \
        '    if ($arg_name != "0") {' \
        '        return 403;' \
        '    }' \
        '    return 200 "ok\n";' \
        '}' > /etc/nginx/publish-check.conf

COPY nginx.conf /etc/nginx/nginx.conf
COPY www/ /www/
COPY docker-entrypoint.d/ /docker-entrypoint.d/
RUN chmod +x /docker-entrypoint.d/*.sh \
    && nginx -t

VOLUME /var/rec

EXPOSE 80 1935

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
