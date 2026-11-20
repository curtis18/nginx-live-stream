#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
env_file=$root/.env
template=$root/haproxy/streams.cfg.template
output=$root/haproxy/streams.cfg

read_env() {
    key=$1
    default=$2

    if [ ! -f "$env_file" ]; then
        printf '%s' "$default"
        return
    fi

    value=$(awk -v key="$key" '
        BEGIN { found = 0; q = sprintf("%c", 39) }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            line = $0
            sub(/\r$/, "", line)
            eq = index(line, "=")
            if (eq == 0) next
            k = substr(line, 1, eq - 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
            if (k != key) next
            v = substr(line, eq + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            if ((substr(v, 1, 1) == "\"" && substr(v, length(v), 1) == "\"") ||
                (substr(v, 1, 1) == q && substr(v, length(v), 1) == q)) {
                v = substr(v, 2, length(v) - 2)
            }
            print v
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' "$env_file") || value=$default

    printf '%s' "$value"
}

fail() {
    echo "haproxy/render.sh: $1" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: haproxy/render.sh [--container N]

Read .env and write local files for the selected streams. The default count
is STREAM_COUNT, or 9 when that setting is absent. N must be from 1 to 9.

  --container N    Run this render for N streams. Overrides STREAM_COUNT.
  --help           Show this help and exit.

Writes compose.yaml, haproxy/streams.cfg, and haproxy/certbot.sh. An empty
CERTBOT_EMAIL leaves the Let's Encrypt account contact unset. Does not edit
/etc/haproxy/haproxy.cfg, run certbot, or reload HAProxy.
EOF
}

check_name() {
    key=$1
    value=$2
    pattern=$3
    if ! printf '%s' "$value" | grep -Eq "$pattern"; then
        fail "$key is not valid: $value"
    fi
}

check_port() {
    key=$1
    value=$2
    case $value in
        ""|*[!0-9]*) fail "$key must be a port number" ;;
    esac
    number=$(printf '%s' "$value" | sed 's/^0*//')
    if [ -z "$number" ]; then
        number=0
    fi
    if [ "$number" -lt 1 ] || [ "$number" -gt 65535 ]; then
        fail "$key must be between 1 and 65535"
    fi
}

check_email() {
    value=$1
    if ! printf '%s' "$value" | grep -Eq '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; then
        fail "CERTBOT_EMAIL is not valid: $value"
    fi
}

check_count() {
    value=$1
    case $value in
        ""|*[!0-9]*) fail "container count must be a number from 1 to 9" ;;
    esac
    number=$(printf '%s' "$value" | sed 's/^0*//')
    if [ -z "$number" ]; then
        number=0
    fi
    if [ "$number" -lt 1 ] || [ "$number" -gt 9 ]; then
        fail "container count must be a number from 1 to 9"
    fi
    printf '%s' "$number"
}

apply_marker() {
    src=$1
    marker=$2
    block=$3
    dest=$4
    awk -v marker="$marker" -v block="$block" '
        $0 == marker {
            found = 1
            while ((getline line < block) > 0) print line
            close(block)
            next
        }
        { print }
        END { if (!found) exit 1 }
    ' "$src" > "$dest"
}

container_arg=""
while [ $# -gt 0 ]; do
    case $1 in
        --help)
            usage
            exit 0
            ;;
        --container)
            if [ $# -lt 2 ]; then
                fail "--container requires a number from 1 to 9"
            fi
            container_arg=$2
            shift 2
            ;;
        --container=*)
            container_arg=${1#--container=}
            shift
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

if ! command -v envsubst >/dev/null 2>&1; then
    fail "envsubst is required (install gettext-base)"
fi

DOMAIN=$(read_env DOMAIN example.com)
HOST_PREFIX=$(read_env HOST_PREFIX stream)
check_name DOMAIN "$DOMAIN" '^[A-Za-z0-9.-]+$'
check_name HOST_PREFIX "$HOST_PREFIX" '^[A-Za-z0-9-]+$'

if [ -n "$container_arg" ]; then
    STREAM_COUNT=$(check_count "$container_arg")
else
    STREAM_COUNT=$(check_count "$(read_env STREAM_COUNT 9)")
fi

ACME_PORT=$(read_env ACME_PORT 9080)
check_port ACME_PORT "$ACME_PORT"
CERTBOT_EMAIL=$(read_env CERTBOT_EMAIL "")
if [ -n "$CERTBOT_EMAIL" ]; then
    check_email "$CERTBOT_EMAIL"
    CERTBOT_ACCOUNT_ARGS="--email \"${CERTBOT_EMAIL}\""
    CERTBOT_HELP_CONTACT="Uses --email ${CERTBOT_EMAIL}."
else
    CERTBOT_ACCOUNT_ARGS="--register-unsafely-without-email"
    CERTBOT_HELP_CONTACT="Uses --register-unsafely-without-email. The Let's Encrypt account contact stays empty."
fi

acls=$(mktemp)
uses=$(mktemp)
backends=$(mktemp)
services=$(mktemp)
proto=$(mktemp)
staged=$(mktemp)
trap 'rm -f "$acls" "$uses" "$backends" "$services" "$proto" "$staged"' EXIT

awk '
    $0 == "# @@SERVICE@@" { capture = 1; next }
    $0 == "# @@END@@" { capture = 0; next }
    capture { print }
' "$root/compose.yaml.template" > "$proto"
if [ ! -s "$proto" ]; then
    fail "compose.yaml.template is missing the service block"
fi

STREAM_NAMES=""
STREAM_NAME_COMMENTS=""
CERTBOT_HELP_NAMES=""
i=1
while [ "$i" -le "$STREAM_COUNT" ]; do
    nn=$(printf '%02d' "$i")
    host="${HOST_PREFIX}${nn}.${DOMAIN}"
    port=$(read_env "HTTP_PORT_$i" $((18079 + i)))
    check_port "HTTP_PORT_$i" "$port"
    rtmp=$((1934 + i))
    http=$((18079 + i))

    printf '    acl known_host hdr(host) -i %s\n' "$host" >> "$acls"
    printf '    use_backend stream%s if { hdr(host) -i %s }\n' "$nn" "$host" >> "$uses"
    cat >> "$backends" <<EOF
backend stream${nn}
    mode http
    option httpchk GET /healthz
    http-check expect status 200
    server stream${nn} 127.0.0.1:${port} check inter 5s fall 3 rise 2

EOF
    sed -e "s/@@N@@/$i/g" -e "s/@@RTMP@@/$rtmp/g" -e "s/@@HTTP@@/$http/g" "$proto" >> "$services"
    echo >> "$services"

    if [ -n "$STREAM_NAMES" ]; then
        STREAM_NAMES="$STREAM_NAMES $host"
    else
        STREAM_NAMES=$host
    fi
    STREAM_NAME_COMMENTS="${STREAM_NAME_COMMENTS}#   ${host}
"
    CERTBOT_HELP_NAMES="${CERTBOT_HELP_NAMES}  ${host}
"
    i=$((i + 1))
done

compose_output=$root/compose.yaml
if ! apply_marker "$root/compose.yaml.template" "# @@SERVICES@@" "$services" "$staged"; then
    fail "compose.yaml.template is missing # @@SERVICES@@"
fi
awk '
    $0 == "# @@SERVICE@@" { skip = 1; next }
    $0 == "# @@END@@" { skip = 0; next }
    skip { next }
    { print }
' "$staged" > "$compose_output"

export DOMAIN HOST_PREFIX ACME_PORT CERTBOT_EMAIL STREAM_NAMES STREAM_NAME_COMMENTS
export CERTBOT_ACCOUNT_ARGS CERTBOT_HELP_CONTACT CERTBOT_HELP_NAMES
subst='${DOMAIN} ${HOST_PREFIX} ${ACME_PORT} ${CERTBOT_EMAIL} ${STREAM_NAMES} ${STREAM_NAME_COMMENTS} ${CERTBOT_ACCOUNT_ARGS} ${CERTBOT_HELP_CONTACT} ${CERTBOT_HELP_NAMES}'

if ! apply_marker "$template" "@@HOST_ACLS@@" "$acls" "$staged"; then
    fail "streams.cfg.template is missing @@HOST_ACLS@@"
fi
if ! apply_marker "$staged" "@@USE_BACKENDS@@" "$uses" "$output"; then
    fail "streams.cfg.template is missing @@USE_BACKENDS@@"
fi
if ! apply_marker "$output" "@@BACKENDS@@" "$backends" "$staged"; then
    fail "streams.cfg.template is missing @@BACKENDS@@"
fi
envsubst "$subst" < "$staged" > "$output"
echo "haproxy/render.sh: wrote $compose_output ($STREAM_COUNT streams)"
echo "haproxy/render.sh: wrote $output"

certbot_output=$root/haproxy/certbot.sh
cert_tmp=$(mktemp)
raw=$(mktemp)
trap 'rm -f "$acls" "$uses" "$backends" "$services" "$proto" "$staged" "$cert_tmp" "$raw"' EXIT
envsubst "$subst" <<'EOF' > "$raw"
#!/bin/sh
# Generated by haproxy/render.sh. Run haproxy/render.sh again to replace it.
# This file does not edit /etc/haproxy/haproxy.cfg.
#
# Review it. Merge haproxy/streams.cfg into the HAProxy configuration and
# reload HAProxy. Run this only when these DNS names point at this host:
#
#   haproxy/certbot.sh --help
#   sudo haproxy/certbot.sh
#
${STREAM_NAME_COMMENTS}
set -eu

usage() {
    cat <<'HELP'
Usage: haproxy/certbot.sh [--help]

Requests one certificate for:
${CERTBOT_HELP_NAMES}
Installs /etc/ssl/private/streams/${HOST_PREFIX}.${DOMAIN}.pem
${CERTBOT_HELP_CONTACT}
Does not edit /etc/haproxy/haproxy.cfg.
HELP
}

case "@D@{1:-}" in
    "")
        ;;
    --help)
        usage
        exit 0
        ;;
    *)
        echo "haproxy/certbot.sh: unknown argument: @D@1" >&2
        exit 1
        ;;
esac
if [ "@D@#" -gt 1 ]; then
    echo "haproxy/certbot.sh: unknown argument: @D@2" >&2
    exit 1
fi

cert_name=${HOST_PREFIX}01.${DOMAIN}
pem=/etc/ssl/private/streams/${HOST_PREFIX}.${DOMAIN}.pem
acme_port=${ACME_PORT}
lineage=/etc/letsencrypt/live/${HOST_PREFIX}01.${DOMAIN}
hook=/etc/letsencrypt/renewal-hooks/deploy/nginx-live-stream.sh
names="${STREAM_NAMES}"

if [ "@D@(id -u)" -ne 0 ]; then
    echo "haproxy/certbot.sh: run as root: sudo haproxy/certbot.sh" >&2
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "haproxy/certbot.sh: openssl is required" >&2
    exit 1
fi

if ! command -v certbot >/dev/null 2>&1; then
    echo "haproxy/certbot.sh: certbot is required" >&2
    exit 1
fi

install -d -m 755 /etc/ssl/private/streams

if [ ! -s "@D@pem" ]; then
    key=@D@(mktemp)
    crt=@D@(mktemp)
    trap 'rm -f "@D@key" "@D@crt"' EXIT
    sans=""
    for name in @D@names; do
        if [ -n "@D@sans" ]; then
            sans="@D@sans,"
        fi
        sans="@D@{sans}DNS:@D@name"
    done
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "@D@key" -out "@D@crt" -days 2 \
        -subj "/CN=@D@cert_name" \
        -addext "subjectAltName=@D@sans"
    cat "@D@crt" "@D@key" > "@D@pem"
    chmod 600 "@D@pem"
    rm -f "@D@key" "@D@crt"
    trap - EXIT
    echo "haproxy/certbot.sh: wrote a temporary certificate at @D@pem"
    echo "haproxy/certbot.sh: merge haproxy/streams.cfg, reload HAProxy, then run this script again."
    exit 0
fi

# HAProxy must already forward /.well-known/acme-challenge/ to 127.0.0.1:@D@acme_port.
set --
for name in @D@names; do
    set -- "@D@@" -d "@D@name"
done
certbot certonly --non-interactive --agree-tos ${CERTBOT_ACCOUNT_ARGS} \
    --preferred-challenges http \
    --standalone --http-01-port "@D@acme_port" \
    --cert-name "@D@cert_name" \
    --keep-until-expiring \
    "@D@@"

umask 077
tmp=@D@(mktemp)
cat "@D@lineage/fullchain.pem" "@D@lineage/privkey.pem" > "@D@tmp"
chmod 600 "@D@tmp"
mv "@D@tmp" "@D@pem"

install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
cat > "@D@hook" <<'HOOK'
#!/bin/sh
set -eu
lineage=/etc/letsencrypt/live/${HOST_PREFIX}01.${DOMAIN}
pem=/etc/ssl/private/streams/${HOST_PREFIX}.${DOMAIN}.pem
if [ "@D@{RENEWED_LINEAGE:-}" != "@D@lineage" ]; then
    exit 0
fi
umask 077
tmp=@D@(mktemp)
cat "@D@lineage/fullchain.pem" "@D@lineage/privkey.pem" > "@D@tmp"
chmod 600 "@D@tmp"
mv "@D@tmp" "@D@pem"
systemctl reload haproxy
HOOK
chmod 755 "@D@hook"

if systemctl list-unit-files snap.certbot.renew.timer >/dev/null 2>&1; then
    systemctl enable --now snap.certbot.renew.timer
else
    echo "haproxy/certbot.sh: snap.certbot.renew.timer was not found" >&2
fi

echo "haproxy/certbot.sh: installed @D@pem"
echo "haproxy/certbot.sh: reload reads the existing HAProxy config and does not rewrite it."
EOF
sed 's/@D@/$/g' "$raw" > "$cert_tmp"
rm -f "$raw"
chmod 755 "$cert_tmp"
mv "$cert_tmp" "$certbot_output"
trap - EXIT
echo "haproxy/render.sh: wrote $certbot_output"
echo "haproxy/render.sh: review it, then run sudo haproxy/certbot.sh when DNS is ready"
