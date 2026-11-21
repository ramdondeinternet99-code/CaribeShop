#!/usr/bin/env bash
# Recolecta evidencias de texto en evidencias/auto/. Ejecutar con el despliegue activo
# y con la sesion `az login` de la suscripcion usada. Complete con capturas de pantalla
# (portal) en evidencias/capturas/ donde el informe lo indique.
# Uso: scripts/evidencias.sh
set -uo pipefail
cd "$(dirname "$0")/.."

OUT=evidencias/auto
mkdir -p "$OUT"
tf() { terraform -chdir=infra output -raw "$1"; }

RG=$(tf resource_group);  VMSS=$(tf vmss_name);  KV=$(tf key_vault_name)
URL=$(tf app_url);        LB_ID=$(tf lb_id);     PID=$(tf vmss_principal_id)
WS=$(tf log_analytics_workspace_id);             AUTOSCALE_ID=$(tf autoscale_id)
SUB=$(az account show --query id -o tsv)

run_vmss() { az vmss run-command invoke -g "$RG" -n "$VMSS" --instance-id 0 \
  --command-id RunShellScript --scripts "$1" --query "value[0].message" -o tsv; }

echo "== S1: backend remoto y repositorio limpio =="
{
  grep -n 'backend "azurerm"' infra/providers.tf
  echo "--- .gitignore (estado y tfvars) ---"; grep -n -E 'tfstate|tfvars' .gitignore
  echo "--- archivos de estado/variables rastreados por Git (debe estar vacio) ---"
  git ls-files | grep -E 'tfstate|\.tfvars$' || echo "(ninguno)"
  echo "--- historial: estado o tfvars alguna vez commiteados (debe estar vacio) ---"
  git log --all --name-only --pretty=format: | grep -E 'tfstate|\.tfvars$' | sort -u || true
} > "$OUT/S1_backend_y_git.txt" 2>&1

echo "== S2: red sin IP publica y NSG =="
{
  echo "--- IP publica de instancias (debe estar vacio) ---"
  az vmss list-instance-public-ips -g "$RG" -n "$VMSS" -o table
  echo "--- reglas del NSG ---"
  az network nsg rule list -g "$RG" --nsg-name "nsg-$(echo "$VMSS" | sed 's/^vmss-//')-app" \
    --query "[].{prioridad:priority,nombre:name,direccion:direction,acceso:access,puertos:destinationPortRange,origen:sourceAddressPrefix,destino:destinationAddressPrefix}" -o table
} > "$OUT/S2_red_nsg.txt" 2>&1

echo "== S3: la app lee el secreto sin mostrarlo =="
{ for i in 1 2 3; do curl -s -m 10 "$URL/secret-check"; echo; done; } > "$OUT/S3_secret_check.txt"

echo "== S4: minimo privilegio de la identidad del VMSS =="
az role assignment list --assignee "$PID" --all \
  --query "[].{rol:roleDefinitionName,alcance:scope}" -o table > "$OUT/S4_roles_vmss.txt" 2>&1

echo "== S5: violar la politica Deny (debe aparecer RequestDisallowedByPolicy) =="
az storage account create -g "$RG" -n "stpol$RANDOM$RANDOM" -l "$(az group show -n "$RG" --query location -o tsv)" \
  --sku Standard_LRS --allow-blob-public-access true > "$OUT/S5_policy_deny.txt" 2>&1 || true

echo "== Demo de seguridad: leer-secreto.sh por Run Command (identidad administrada) =="
run_vmss "/usr/local/bin/leer-secreto.sh" > "$OUT/S3_leer_secreto_runcommand.txt" 2>&1

echo "== S6: KQL - lectura del secreto por la identidad del VMSS =="
az monitor log-analytics query -w "$WS" --timespan P1D -o table --analytics-query '
union isfuzzy=true
  (AZKVAuditLogs | project TimeGenerated, OperationName, ResultSignature, IP = CallerIpAddress, Quien = tostring(Identity.claim.oid)),
  (AzureDiagnostics | where ResourceProvider == "MICROSOFT.KEYVAULT"
     | project TimeGenerated, OperationName, ResultSignature, IP = CallerIPAddress, Quien = column_ifexists("identity_claim_oid_g", ""))
| where OperationName in ("SecretGet", "SecretSet")
| order by TimeGenerated desc' > "$OUT/S6_kql_secretos.txt" 2>&1
echo "(principal_id del VMSS para comparar con la columna Quien: $PID)" >> "$OUT/S6_kql_secretos.txt"

echo "== E1: instancias y zonas =="
az vmss list-instances -g "$RG" -n "$VMSS" \
  --query "[].{instancia:instanceId,nombre:name,zona:zones[0],estado:provisioningState}" -o table > "$OUT/E1_instancias_zonas.txt" 2>&1

echo "== E2: sonda de salud y metrica Health Probe Status =="
{
  az network lb probe list -g "$RG" --lb-name "$(basename "$LB_ID")" \
    --query "[].{nombre:name,protocolo:protocol,puerto:port,ruta:requestPath,intervalo:intervalInSeconds,umbral:probeThreshold}" -o table
  echo "--- DipAvailability (Health Probe Status) ultima hora ---"
  az monitor metrics list --resource "$LB_ID" --metric DipAvailability --interval PT1M --offset 1h \
    --aggregation Average -o table
} > "$OUT/E2_sonda.txt" 2>&1

echo "== E3: autoscale (reglas e historial) =="
{
  az monitor autoscale show --ids "$AUTOSCALE_ID" \
    --query "profiles[0].{min:capacity.minimum,max:capacity.maximum,reglas:rules[].{metrica:metricTrigger.metricName,op:metricTrigger.operator,umbral:metricTrigger.threshold,ventana:metricTrigger.timeWindow,accion:scaleAction.direction,cooldown:scaleAction.cooldown}}" -o json
  echo "--- AutoscaleScaleActions en Log Analytics (ultimas 24 h) ---"
  az monitor log-analytics query -w "$WS" --timespan P1D -o table \
    --analytics-query 'AutoscaleScaleActions | project TimeGenerated, ScaleDirection, OldInstanceCount, NewInstanceCount, Message | order by TimeGenerated asc'
} > "$OUT/E3_autoscale.txt" 2>&1

echo "== E3 (extra): eventos de autoscale en el Activity Log y CPU del VMSS =="
{
  az monitor activity-log list -g "$RG" --offset 3h \
    --query "[?contains(operationName.value, 'autoscale')].{hora:eventTimestamp, evento:operationName.localizedValue, estado:status.value}" -o table
  echo "--- CPU promedio por minuto (ultima hora) ---"
  az monitor metrics list --resource "$(tf vmss_id)" --metric "Percentage CPU" --interval PT1M --aggregation Average --offset 1h -o table
} > "$OUT/E3_autoscale_eventos_cpu.txt" 2>&1

echo "== E4: instancias (para comparar antes/despues de una reparacion) =="
az vmss list-instances -g "$RG" -n "$VMSS" \
  --query "[].{instancia:instanceId,nombre:name,estado:provisioningState,modeloAplicado:latestModelApplied}" -o table > "$OUT/E4_instancias.txt" 2>&1

echo "== E5: alertas configuradas =="
az monitor metrics alert list -g "$RG" \
  --query "[].{nombre:name,severidad:severity,habilitada:enabled,ventana:windowSize}" -o table > "$OUT/E5_alertas.txt" 2>&1

echo "== P3.2: filtrado de salida (egress) desde la instancia 0 =="
run_vmss "curl -s -m 5 -o /dev/null https://example.com && echo 'internet: ABIERTO' || echo 'internet: BLOQUEADO'; curl -s -m 5 -o /dev/null -w 'keyvault: %{http_code}' 'https://$KV.vault.azure.net/secrets?api-version=7.4'" \
  > "$OUT/P3_2_egress.txt" 2>&1

cat <<EOF

Evidencias de texto guardadas en $OUT/ (suscripcion $SUB).
Faltan, por ser manuales:
  - P3.1: desde Azure Cloud Shell ->  az keyvault secret show --vault-name $KV -n $(tf secret_name) --query value -o tsv   (debe dar Forbidden; NO imprima el valor si funciona)
  - E3/E4/E5: capturas del portal (historial de ejecucion del autoscale, reparacion de instancia, correo de alerta)
  - P1/P2: CSV/HTML de Locust y CSV/PNG de analizar_falla.py
EOF
