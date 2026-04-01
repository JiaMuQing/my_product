#!/usr/bin/env bash
# Deploy static landing page to server. Reads connection info from docs/infrastructure.md (gitignored).
# Uses scp only (no rsync on remote required). Never uploads docs/.

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFRA="${ROOT}/docs/infrastructure.md"
SRC="${ROOT}/index.html"

die() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "$INFRA" ]] || die "missing ${INFRA} — copy from docs/infrastructure.example.md and fill in."
[[ -f "$SRC" ]] || die "missing ${SRC}"
command -v scp >/dev/null 2>&1 || die "scp not found (need OpenSSH client)"
command -v ssh >/dev/null 2>&1 || die "ssh not found"

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
DEST="${SSH_USER}@${SSH_HOST}:${REMOTE_PATH}/index.html"

echo "→ ${DEST}"

ssh_key_mkdir() {
  ssh -o BatchMode=yes "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "mkdir -p ${REMOTE_PATH}"
}

ssh_key_scp() {
  scp -o BatchMode=yes "${SSH_OPTS[@]}" "$SRC" "$DEST"
}

ssh_pass_mkdir() {
  [[ -n "$SSH_PASS" ]] || die "could not parse 密码 from ${INFRA}. For key login: ssh-copy-id ${SSH_USER}@${SSH_HOST}"
  command -v sshpass >/dev/null 2>&1 || die "need sshpass for password login. macOS: brew install sshpass"
  SSHPASS="$SSH_PASS" sshpass -e ssh "${SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    "${SSH_USER}@${SSH_HOST}" "mkdir -p ${REMOTE_PATH}"
}

ssh_pass_scp() {
  SSHPASS="$SSH_PASS" sshpass -e scp "${SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    "$SRC" "$DEST"
}

if ssh_key_mkdir 2>/dev/null && ssh_key_scp 2>/dev/null; then
  echo "done (SSH key)."
  exit 0
fi

ssh_pass_mkdir
ssh_pass_scp
echo "done (password from local docs/infrastructure.md only; index.html is the only file uploaded)."
