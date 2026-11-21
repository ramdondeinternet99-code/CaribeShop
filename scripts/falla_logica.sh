#!/usr/bin/env bash
# P2.1 - Falla logica: /health de UNA instancia responde 503.
# Uso: scripts/falla_logica.sh [instance_id=1]
# Antes: lance Locust con carga moderada y scripts/monitor.py en otra terminal.
set -euo pipefail
cd "$(dirname "$0")/.."

RG=$(terraform -chdir=infra output -raw resource_group)
VMSS=$(terraform -chdir=infra output -raw vmss_name)
ID="${1:-1}"
mkdir -p evidencias/p2

echo ">> Marcando la instancia $ID como NO sana (hora tomada EN la instancia)..."
az vmss run-command invoke -g "$RG" -n "$VMSS" --instance-id "$ID" \
  --command-id RunShellScript \
  --scripts "touch /var/run/app-unhealthy && date +%s" \
  --query "value[0].message" -o tsv | tee evidencias/p2/t0_logica.txt

cat <<EOF

Listo. Deje correr el monitor ~2 minutos y analice:
  python3 scripts/analizar_falla.py evidencias/p2/monitor_logica.csv \\
      --t0-file evidencias/p2/t0_logica.txt --instancia _$ID --ventana 120

E4: si deja la instancia no sana mas alla del periodo de gracia (10 min), la reparacion
automatica la reemplaza. Evidencia: portal -> VMSS -> Instancias (ID/hora de creacion)
y 'az vmss list-instances'. Para restaurarla antes: scripts/restaurar_salud.sh $ID
EOF
