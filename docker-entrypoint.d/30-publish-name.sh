#!/bin/sh
set -eu

if [ ! -f /www/stream.json ]; then
    echo "publish-name: /www/stream.json is missing" >&2
    exit 1
fi

name=$(tr -d '\n' < /www/stream.json | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

case "$name" in
    ""|*[!A-Za-z0-9._-]*)
        echo "publish-name: stream.json name must contain only letters, digits, '.', '_' or '-'" >&2
        exit 1
        ;;
esac

tmp=$(mktemp /etc/nginx/publish-check.conf.XXXXXX)
trap 'rm -f "$tmp"' EXIT
{
    printf '%s\n' 'location = /internal/publish-check {'
    printf '%s\n' '    default_type text/plain;'
    printf '%s\n' '    access_log off;'
    printf '    if ($arg_name != "%s") {\n' "$name"
    printf '%s\n' '        return 403;'
    printf '%s\n' '    }'
    printf '%s\n' '    return 200 "ok\n";'
    printf '%s\n' '}'
} > "$tmp"
mv "$tmp" /etc/nginx/publish-check.conf
trap - EXIT

echo "publish-name: accepting RTMP stream key '${name}'"
