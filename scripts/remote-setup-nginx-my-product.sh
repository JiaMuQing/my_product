#!/usr/bin/env bash
# One-shot: install/configure Nginx on the ECS so product.xyptkd.cn serves the static site root.
# Reads SSH host/user/password from docs/infrastructure.md (same as deploy-my-product.sh).
# Run from repo root: ./scripts/remote-setup-nginx-my-product.sh

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFRA="${ROOT}/docs/infrastructure.md"
NGINX_CONF_SRC="${ROOT}/scripts/nginx-product.xyptkd.cn.conf"

die() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "$INFRA" ]] || die "missing ${INFRA}"
[[ -f "$NGINX_CONF_SRC" ]] || die "missing ${NGINX_CONF_SRC}"

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
  command -v sshpass >/dev/null 2>&1 || die "need sshpass for password login (brew install sshpass)"
  SSHPASS="$SSH_PASS" sshpass -e scp "${SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    "$src" "$dest"
}

run_ssh() {
  if ssh -o BatchMode=yes "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$@" 2>/dev/null; then
    return 0
  fi
  [[ -n "$SSH_PASS" ]] || die "SSH key failed and no 密码 in ${INFRA}"
  command -v sshpass >/dev/null 2>&1 || die "need sshpass for password login (brew install sshpass)"
  SSHPASS="$SSH_PASS" sshpass -e ssh "${SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    "${SSH_USER}@${SSH_HOST}" "$@"
}

echo "→ ${SSH_USER}@${SSH_HOST}: upload nginx conf + install nginx"
scp_put "$NGINX_CONF_SRC" "${SSH_USER}@${SSH_HOST}:/tmp/product.xyptkd.cn.conf"

run_ssh "WEB_ROOT=${REMOTE_PATH}" bash -s <<'REMOTE'
set -euo pipefail
mkdir -p "$WEB_ROOT"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq nginx
elif command -v yum >/dev/null 2>&1; then
  yum install -y nginx
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx
else
  echo "error: no apt-get/yum/dnf found" >&2
  exit 1
fi

sed -i "s|root /var/web/my_product;|root ${WEB_ROOT};|" /tmp/product.xyptkd.cn.conf
install -m 0644 /tmp/product.xyptkd.cn.conf /etc/nginx/conf.d/product.xyptkd.cn.conf

if [[ -f /etc/nginx/sites-enabled/default ]]; then
  rm -f /etc/nginx/sites-enabled/default || true
fi

nginx -t
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable nginx
  systemctl restart nginx
else
  service nginx restart
fi

if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=http 2>/dev/null || true
  firewall-cmd --permanent --add-service=https 2>/dev/null || true
  firewall-cmd --reload 2>/dev/null || true
fi

echo "OK: nginx -> ${WEB_ROOT} (product.xyptkd.cn)"
REMOTE

echo "done. Test: curl -sI -m 10 http://${SSH_HOST}/ -H 'Host: product.xyptkd.cn'"
