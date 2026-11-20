#!/bin/sh
set -eu

user="${CONTROL_USER:-}"
pass="${CONTROL_PASSWORD:-}"
pass_file="${CONTROL_PASSWORD_FILE:-}"

if [ -n "$pass_file" ]; then
    if [ ! -r "$pass_file" ]; then
        echo "control-auth: CONTROL_PASSWORD_FILE is not readable: $pass_file" >&2
        exit 1
    fi
    pass="$(cat "$pass_file")"
fi

if [ -z "$user" ] || [ -z "$pass" ]; then
    echo "control-auth: credentials not set; /control disabled and /stat is container-local only"
    cat > /etc/nginx/control.conf <<'EOF'
location ^~ /control/ {
    return 404;
}

location = /stat {
    allow 127.0.0.1;
    allow ::1;
    deny all;
    default_type text/xml;
    rtmp_stat all;
}
EOF
    exit 0
fi

case "$user" in
    *:*|*'
'*) echo "control-auth: CONTROL_USER must not contain ':' or a newline" >&2; exit 1 ;;
esac

case "$pass" in
    *'
'*) echo "control-auth: password must not contain a newline" >&2; exit 1 ;;
esac

hash="$(printf '%s' "$pass" | openssl passwd -apr1 -stdin)"
printf '%s:%s\n' "$user" "$hash" > /etc/nginx/control.htpasswd
chmod 0644 /etc/nginx/control.htpasswd

cat > /etc/nginx/control.conf <<'EOF'
location ^~ /control/ {
    auth_basic "Stream admin";
    auth_basic_user_file /etc/nginx/control.htpasswd;
    limit_except GET { deny all; }
    rtmp_control all;
}

location = /stat {
    auth_basic "Stream admin";
    auth_basic_user_file /etc/nginx/control.htpasswd;
    default_type text/xml;
    rtmp_stat all;
}
EOF

echo "control-auth: /control and /stat enabled for user '$user'"
