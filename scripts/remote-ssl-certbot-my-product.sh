#!/usr/bin/env bash
# Obtain/renew Let's Encrypt cert (webroot), install HTTPS nginx config, install cron for renew.
# Requires: DNS product.xyptkd.cn -> this host; inbound TCP 80 (and 443 after TLS) open.
# Reads SSH from docs/infrastructure.md. Run from repo root:
#   ./scripts/remote-ssl-certbot-my-product.sh

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFRA="${ROOT}/docs/infrastructure.md"
CONF_HTTP="${ROOT}/scripts/nginx-product.xyptkd.cn.conf"
CONF_FULL="${ROOT}/scripts/nginx-product.xyptkd.cn.full.conf"
CERT_DOMAIN="product.xyptkd.cn"

die() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "$INFRA" ]] || die "missing ${INFRA}"
[[ -f "$CONF_HTTP" ]] || die "missing ${CONF_HTTP}"
[[ -f "$CONF_FULL" ]] || die "missing ${CONF_FULL}"

SSH_PASS="$(sed -n 's/^[[:space:]]*密码[[:space:]]*//p' "$INFRA" | head -1 | tr -d '\r')"
SSH_USER="$(sed -n 's/^[[:space:]]*账号[[:space:]]*//p' "$INFRA" | head -1 | tr -d '\r')"
SSH_HOST="$(sed -n 's/^[[:space:]]*ip[[:space:]]*//p' "$INFRA" | head -1 | tr -d '\r' | tr -d '[:space:]')"

REMOTE_REL="$(grep -E 'my_product[[:space:]].*部署在' "$INFRA" | sed -n 's/.*部署在[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1 | tr -d '\r')"
[[ -n "$REMOTE_REL" ]] || REMOTE_REL="var/web/my_product"
if [[ "${REMOTE_REL}" != /* ]]; then
  REMOTE_PATH="/${REMOTE_REL}"
else
  REMOTE_PATH="${REMOTE_REL}"
fi

[[ -n "$SSH_USER" && -n "$SSH_HOST" ]] || die "could not parse 账号 / ip from ${INFRA}"

SSH_OPTS=( -o StrictHostKeyChecking=accept-new )

scp_put() {
  local src="$1" dest="$2"
  if scp -o BatchMode=yes "${SSH_OPTS[@]}" "$src" "$dest" 2>/dev/null; then
    return 0
  fi
  [[ -n "$SSH_PASS" ]] || die "SSH key scp failed and no 密码 in ${INFRA}"
  command -v sshpass >/dev/null 2>&1 || die "need sshpass (brew install sshpass)"
  SSHPASS="$SSH_PASS" sshpass -e scp "${SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    "$src" "$dest"
}

run_ssh() {
  if ssh -o BatchMode=yes "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$@" 2>/dev/null; then
    return 0
  fi
  [[ -n "$SSH_PASS" ]] || die "SSH key failed and no 密码 in ${INFRA}"
  command -v sshpass >/dev/null 2>&1 || die "need sshpass (brew install sshpass)"
  SSHPASS="$SSH_PASS" sshpass -e ssh "${SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    "${SSH_USER}@${SSH_HOST}" "$@"
}

echo "→ ${SSH_USER}@${SSH_HOST}: certbot + TLS nginx + cron"

scp_put "$CONF_HTTP" "${SSH_USER}@${SSH_HOST}:/tmp/product.xyptkd.cn.http.conf"
scp_put "$CONF_FULL" "${SSH_USER}@${SSH_HOST}:/tmp/product.xyptkd.cn.full.conf"

run_ssh "WEB_ROOT=${REMOTE_PATH} CERT_DOMAIN=${CERT_DOMAIN}" bash -s <<'REMOTE'
set -euo pipefail
mkdir -p "$WEB_ROOT"
mkdir -p /var/www/certbot

sed -i "s|root /var/web/my_product;|root ${WEB_ROOT};|g" /tmp/product.xyptkd.cn.http.conf
sed -i "s|root /var/web/my_product;|root ${WEB_ROOT};|g" /tmp/product.xyptkd.cn.full.conf

install -m 0644 /tmp/product.xyptkd.cn.http.conf /etc/nginx/conf.d/product.xyptkd.cn.conf

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq certbot nginx
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx certbot 2>/dev/null || yum install -y nginx certbot 2>/dev/null || true
  if ! command -v certbot >/dev/null 2>&1; then
    dnf install -y epel-release 2>/dev/null || true
    dnf install -y certbot 2>/dev/null || yum install -y certbot 2>/dev/null || true
  fi
elif command -v yum >/dev/null 2>&1; then
  yum install -y nginx certbot 2>/dev/null || true
  if ! command -v certbot >/dev/null 2>&1; then
    yum install -y epel-release 2>/dev/null || true
    yum install -y certbot 2>/dev/null || true
  fi
else
  echo "error: need apt-get, dnf, or yum" >&2
  exit 1
fi
command -v certbot >/dev/null 2>&1 || { echo "error: certbot not installed (enable EPEL or install certbot manually)" >&2; exit 1; }

nginx -t
systemctl reload nginx 2>/dev/null || systemctl restart nginx

CERT_PATH="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"
if [[ ! -f "$CERT_PATH" ]]; then
  if ! certbot certonly \
    --webroot -w /var/www/certbot \
    -d "$CERT_DOMAIN" \
    --agree-tos --non-interactive \
    --register-unsafely-without-email \
    --keep-until-expiring; then
    echo "" >&2
    echo "certbot (HTTP-01) failed. Common cause: Cloudflare orange-cloud + Error 522 so Let's Encrypt cannot fetch /.well-known/ on port 80." >&2
    echo "Fix: Cloudflare DNS → set product A record to DNS only (gray cloud), ensure Aliyun SG allows TCP 80, re-run this script, then turn proxy back on." >&2
    echo "Or use DNS-01 with a Cloudflare API token (see README)." >&2
    exit 1
  fi
else
  echo "cert already present: $CERT_PATH"
fi

install -m 0644 /tmp/product.xyptkd.cn.full.conf /etc/nginx/conf.d/product.xyptkd.cn.conf
nginx -t
systemctl reload nginx

CRON_FILE=/etc/cron.d/letsencrypt-renew-nginx
cat > "$CRON_FILE" <<'CRON'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# Renew twice daily; reload nginx only when certbot actually renews.
0 3,15 * * * root certbot renew --quiet --deploy-hook "/usr/bin/systemctl reload nginx"
CRON
chmod 644 "$CRON_FILE"

echo "OK: TLS active for ${CERT_DOMAIN}; cron installed at ${CRON_FILE}"
REMOTE

echo "done. Check: curl -sI https://${CERT_DOMAIN}/"
