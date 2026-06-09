#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEPLOY_TARGET="${DEPLOY_TARGET:-agent_vps}"
DEPLOY_PORT="${DEPLOY_PORT:-}"
REMOTE_APP_DIR="${REMOTE_APP_DIR:-/home/manuel/apps/twenty-crm}"
PUBLIC_HEALTH_URL="${PUBLIC_HEALTH_URL:-https://crm.instabloom.gt/healthz}"

SSH_ARGS=(-o BatchMode=yes)
if [[ -n "$DEPLOY_PORT" ]]; then
  SSH_ARGS+=(-p "$DEPLOY_PORT")
fi

RSYNC_RSH="ssh"
for arg in "${SSH_ARGS[@]}"; do
  RSYNC_RSH+=" $(printf '%q' "$arg")"
done

echo "Deploying Twenty CRM to ${DEPLOY_TARGET}:${REMOTE_APP_DIR}"

ssh "${SSH_ARGS[@]}" "$DEPLOY_TARGET" "mkdir -p '$REMOTE_APP_DIR'"

rsync -az --delete \
  --exclude .env \
  --exclude admin-bootstrap.txt \
  --exclude data \
  --exclude backups \
  --exclude .DS_Store \
  -e "$RSYNC_RSH" \
  "$DEPLOY_DIR/" "$DEPLOY_TARGET:$REMOTE_APP_DIR/"

ssh "${SSH_ARGS[@]}" "$DEPLOY_TARGET" "REMOTE_APP_DIR='$REMOTE_APP_DIR' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

cd "$REMOTE_APP_DIR"
touch .env
chmod 600 .env

get_env() {
  grep -E "^$1=" .env | tail -n 1 | cut -d= -f2- || true
}

upsert_env() {
  key="$1"
  value="$2"
  tmp="$(mktemp)"
  if grep -qE "^${key}=" .env; then
    awk -v key="$key" -v value="$value" 'BEGIN { replaced=0 } index($0, key "=") == 1 { print key "=" value; replaced=1; next } { print } END { if (!replaced) print key "=" value }' .env > "$tmp"
  else
    cp .env "$tmp"
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" .env
  chmod 600 .env
}

ensure_secret() {
  key="$1"
  command="$2"
  if [[ -z "$(get_env "$key")" ]]; then
    value="$(eval "$command")"
    upsert_env "$key" "$value"
  fi
}

while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  upsert_env "$key" "$value"
done < release.env

upsert_env PG_DATABASE_USER "$(get_env PG_DATABASE_USER || true)"
if [[ -z "$(get_env PG_DATABASE_USER)" ]]; then
  upsert_env PG_DATABASE_USER twenty
fi
upsert_env PG_DATABASE_HOST db
upsert_env PG_DATABASE_PORT 5432
upsert_env REDIS_URL redis://redis:6379

ensure_secret PG_DATABASE_PASSWORD "openssl rand -hex 24"
ensure_secret ENCRYPTION_KEY "openssl rand -base64 32"
ensure_secret APP_SECRET "openssl rand -base64 32"

if [[ -z "$(get_env CLOUDFLARE_TUNNEL_TOKEN)" ]]; then
  echo "Missing CLOUDFLARE_TUNNEL_TOKEN in $REMOTE_APP_DIR/.env" >&2
  exit 1
fi

docker compose --env-file .env -f compose.yaml pull
docker compose --env-file .env -f compose.yaml up -d

for i in $(seq 1 80); do
  if curl -fsS http://127.0.0.1:3000/healthz >/dev/null; then
    break
  fi
  if [[ "$i" -eq 80 ]]; then
    docker compose --env-file .env -f compose.yaml ps
    docker compose --env-file .env -f compose.yaml logs --tail=120 server
    exit 1
  fi
  sleep 3
done

if command -v node >/dev/null 2>&1; then
  node scripts/bootstrap-admin.js
else
  echo "Node is not available on the VPS, skipping admin bootstrap." >&2
fi

docker compose --env-file .env -f compose.yaml ps
REMOTE_SCRIPT

if command -v curl >/dev/null 2>&1; then
  for i in $(seq 1 40); do
    if curl -fsS --max-time 20 "$PUBLIC_HEALTH_URL" >/dev/null; then
      echo "Public health check passed: $PUBLIC_HEALTH_URL"
      exit 0
    fi
    sleep 3
  done
  echo "Public health check failed: $PUBLIC_HEALTH_URL" >&2
  exit 1
fi

echo "Deployment complete."
