#!/bin/bash
set -euo pipefail
for attempt in $(seq 1 10); do
  if dnf install -y docker; then break; fi
  if [ "$attempt" -eq 10 ]; then exit 1; fi
  sleep 15
done
systemctl enable --now docker
install -d -m 0755 /opt/reservas
# Código e segredo chegam via SSH pelo scripts/deploy.sh, nunca pelo user_data.
