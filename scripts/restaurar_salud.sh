#!/usr/bin/env bash
# Restaura una instancia marcada como no sana (deshace falla_logica.sh).
# Uso: scripts/restaurar_salud.sh [instance_id=1]
set -euo pipefail
cd "$(dirname "$0")/.."

RG=$(terraform -chdir=infra output -raw resource_group)
VMSS=$(terraform -chdir=infra output -raw vmss_name)
ID="${1:-1}"

az vmss run-command invoke -g "$RG" -n "$VMSS" --instance-id "$ID" \
  --command-id RunShellScript \
  --scripts "rm -f /var/run/app-unhealthy && echo restaurada" \
  --query "value[0].message" -o tsv
