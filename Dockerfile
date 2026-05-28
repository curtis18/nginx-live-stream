ARG NGINX_VERSION=1.30.2
ARG ALPINE_VERSION=3.23
ARG NGINX_RTMP_MODULE_VERSION=1.2.2

FROM alpine:${ALPINE_VERSION} AS builder

ARG NGINX_VERSION
ARG NGINX_RTMP_MODULE_VERSION

RUN apk add --no-cache \
        gcc \
        libc-dev \
        make \
        openssl-dev \
        pcre-dev \
        zlib-dev \
        wget \
        tar

RUN wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O /tmp/nginx.tar.gz \
    && tar -xzf /tmp/nginx.tar.gz -C /tmp

RUN wget -q "https://github.com/arut/nginx-rtmp-module/archive/refs/tags/v${NGINX_RTMP_MODULE_VERSION}.tar.gz" -O /tmp/rtmp.tar.gz \
    && tar -xzf /tmp/rtmp.tar.gz -C /tmp \
    && mv /tmp/nginx-rtmp-module-* /tmp/nginx-rtmp-module

RUN cd "/tmp/nginx-${NGINX_VERSION}" \
    && ./configure \
        --with-compat \
        --add-dynamic-module=../nginx-rtmp-module \
    && make modules

FROM nginx:${NGINX_VERSION}-alpine${ALPINE_VERSION}

ARG NGINX_VERSION

COPY --from=builder "/tmp/nginx-${NGINX_VERSION}/objs/ngx_rtmp_module.so" /etc/nginx/modules/

RUN apk add --no-cache \
        openssl \
        ffmpeg \
        wget \
    && mkdir -p /www /var/sock /var/rec /tmp/live /tmp/hls /etc/nginx/logs \
    && chown -R nginx:nginx /www /var/sock /var/rec /tmp/live /tmp/hls

COPY nginx.conf /etc/nginx/nginx.conf
COPY stat.xsl /etc/nginx/static/stat.xsl
COPY index.html /www/index.html

VOLUME /var/rec

EXPOSE 80 1935

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
