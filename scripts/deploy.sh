#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
SSH_KEY="${SSH_KEY:-.keys/devops}"
if [[ ! -f "$SSH_KEY" ]]; then echo 'Chave privada não encontrada em .keys/devops; defina SSH_KEY.' >&2; exit 1; fi
if [[ -z "${TF_VAR_db_password:-}" ]]; then
  read -r -s -p 'Senha usada no RDS: ' TF_VAR_db_password
  printf '\n'
  export TF_VAR_db_password
fi
if [[ ! "$TF_VAR_db_password" =~ ^[A-Za-z0-9_-]{16,64}$ ]]; then echo 'Senha inválida.' >&2; exit 1; fi
export DB_HOST DB_NAME DB_USER
DB_HOST="$(terraform -chdir=infra output -raw rds_address)"
DB_NAME="$(terraform -chdir=infra output -raw db_name)"
DB_USER="$(terraform -chdir=infra output -raw db_username)"
EC2_IP="$(terraform -chdir=infra output -raw ec2_public_ip)"
REMOTE="ec2-user@$EC2_IP"
SSH_ARGS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
STAGING="$(mktemp -d)"
REMOTE_TMP=''
cleanup() {
  rm -rf "$STAGING"
  if [[ -n "$REMOTE_TMP" ]]; then
    ssh "${SSH_ARGS[@]}" "$REMOTE" "rm -rf -- '$REMOTE_TMP'" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
# Gera os arquivos temporários sem imprimir segredos ou incluí-los no Git.
python3 - "$STAGING" <<'PY'
import os, pathlib, shutil, sys
stage = pathlib.Path(sys.argv[1])
shutil.copytree('app', stage / 'app', ignore=shutil.ignore_patterns('node_modules', '.env', '.env.*', '*.log'))
values = {
    'NODE_ENV': 'production', 'PORT': '3000', 'DB_PORT': '5432',
    'DB_HOST': os.environ['DB_HOST'], 'DB_NAME': os.environ['DB_NAME'],
    'DB_USER': os.environ['DB_USER'], 'DB_PASSWORD': os.environ['TF_VAR_db_password'],
    'DB_SSL': 'true', 'DB_SSL_CA': '/app/certs/us-east-1-bundle.pem',
}
(stage / 'api.env').write_text(''.join(f'{key}={value}\n' for key, value in values.items()))
PY
mkdir -p "$STAGING/certs"
curl --fail --silent --show-error --location --retry 3 \
  https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem \
  -o "$STAGING/certs/us-east-1-bundle.pem"
tar -C "$STAGING" -czf "$STAGING/deploy.tar.gz" app certs api.env
printf 'Aguardando SSH em %s...\n' "$EC2_IP"
READY=false
for attempt in $(seq 1 60); do
  if ssh "${SSH_ARGS[@]}" "$REMOTE" true 2>/dev/null; then READY=true; break; fi
  sleep 5
done
if [[ "$READY" != true ]]; then echo 'SSH indisponível. Confira seu IP /32, chave e status da EC2.' >&2; exit 1; fi
ssh "${SSH_ARGS[@]}" "$REMOTE" 'sudo cloud-init status --wait >/dev/null && sudo systemctl is-active --quiet docker'
REMOTE_TMP="$(ssh "${SSH_ARGS[@]}" "$REMOTE" 'umask 077; mktemp -d /tmp/reservas.XXXXXXXX')"
if [[ ! "$REMOTE_TMP" =~ ^/tmp/reservas\.[A-Za-z0-9]+$ ]]; then echo 'Diretório remoto inválido.' >&2; exit 1; fi
scp "${SSH_ARGS[@]}" "$STAGING/deploy.tar.gz" "$REMOTE:$REMOTE_TMP/deploy.tar.gz"
ssh "${SSH_ARGS[@]}" "$REMOTE" "bash -s -- '$REMOTE_TMP'" <<'REMOTE_SCRIPT'
set -euo pipefail
umask 077
stage="$1"
trap 'rm -rf -- "$stage"' EXIT
tar -xzf "$stage/deploy.tar.gz" -C "$stage"
sudo install -d -m 0755 /opt/reservas/certs
sudo install -m 0600 "$stage/api.env" /opt/reservas/api.env
sudo install -m 0644 "$stage/certs/us-east-1-bundle.pem" /opt/reservas/certs/us-east-1-bundle.pem
sudo docker build -t technova-reservas:latest "$stage/app"
sudo docker rm -f technova-reservas >/dev/null 2>&1 || true
sudo docker run -d --name technova-reservas --restart unless-stopped --init \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=16m --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 256m --cpus 1 \
  --log-opt max-size=10m --log-opt max-file=3 \
  --env-file /opt/reservas/api.env \
  --mount type=bind,src=/opt/reservas/certs,dst=/app/certs,readonly \
  -p 3000:3000 technova-reservas:latest
for attempt in $(seq 1 60); do
  if curl --fail --silent --max-time 8 http://127.0.0.1:3000/health; then
    printf '\nAPI conectada ao RDS.\n'; exit 0
  fi
  sleep 5
done
sudo docker logs --tail 80 technova-reservas
exit 1
REMOTE_SCRIPT
printf 'Deploy concluído: http://%s:3000/health\n' "$EC2_IP"
