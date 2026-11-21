#!/usr/bin/env bash
# P2.2 - Falla abrupta: se ELIMINA una instancia durante carga moderada.
# Uso: scripts/falla_abrupta.sh [instance_id=0] [instancias_minimas=2]
# Mide el tiempo hasta recuperar la capacidad minima (instancias 'Succeeded').
set -euo pipefail
cd "$(dirname "$0")/.."

RG=$(terraform -chdir=infra output -raw resource_group)
VMSS=$(terraform -chdir=infra output -raw vmss_name)
ID="${1:-0}"
MINIMO="${2:-2}"
mkdir -p evidencias/p2

T0=$(date +%s)
echo "$T0" > evidencias/p2/t0_abrupta.txt
echo ">> t0 (epoch local) = $T0. Eliminando la instancia $ID..."
az vmss delete-instances -g "$RG" -n "$VMSS" --instance-ids "$ID" --no-wait

echo ">> Esperando recuperar $MINIMO instancias sanas (Succeeded)..."
while true; do
  OK=$(az vmss list-instances -g "$RG" -n "$VMSS" \
        --query "length([?provisioningState=='Succeeded'])" -o tsv)
  AHORA=$(date +%s)
  echo "t0+$((AHORA - T0))s -> instancias Succeeded: $OK"
  if [ "$OK" -ge "$MINIMO" ] && [ $((AHORA - T0)) -gt 30 ]; then
    echo "RECUPERADO en $((AHORA - T0)) s" | tee evidencias/p2/recuperacion_abrupta.txt
    break
  fi
  sleep 10
done

cat <<EOF

Detenga el monitor y analice:
  python3 scripts/analizar_falla.py evidencias/p2/monitor_abrupta.csv \\
      --t0-file evidencias/p2/t0_abrupta.txt --ventana 300
EOF
