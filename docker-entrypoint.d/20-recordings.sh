#!/bin/sh
set -eu

slot="${RECORD_SLOT:-}"

case "$slot" in
    stream-[1-9]) ;;
    *)
        echo "recordings: RECORD_SLOT must be stream-1 through stream-9" >&2
        exit 1
        ;;
esac

mkdir -p "/var/rec/${slot}"
chown nginx:nginx /var/rec "/var/rec/${slot}"
chmod 755 /var/rec "/var/rec/${slot}"

tmp=$(mktemp /etc/nginx/record-path.conf.XXXXXX)
trap 'rm -f "$tmp"' EXIT
printf 'record_path /var/rec/%s;\n' "$slot" > "$tmp"
mv "$tmp" /etc/nginx/record-path.conf
trap - EXIT

echo "recordings: writing to /var/rec/${slot}"
