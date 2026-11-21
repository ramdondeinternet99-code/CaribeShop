# CaribeShop - plataforma segura, escalable y altamente disponible en Azure

Taller integrador de *Infraestructura para TI* (UTB). Todo se despliega como código con
Terraform y se valida con un pipeline DevSecOps (GitHub Actions + Checkov), pruebas de
carga (Locust) y pruebas de falla.

## Arquitectura

```mermaid
flowchart TB
    Internet(["🌐 Internet"])
    Pip["IP pública Standard<br/>(Zonal-redundante: Zonas 1, 2, 3)"]
    LB["Load Balancer Standard<br/>Sonda HTTP /health (5 s × 2 fallos)"]

    subgraph RG["Grupo de recursos (gobernado por Azure Policy - Deny)"]
        direction TB

        subgraph VNet["Red Virtual · Subred: snet-app"]
            direction TB
            NSG["NSG: HTTP desde Internet y sonda LB<br/>SSH/RDP denegados · Egress solo AzureKeyVault"]

            subgraph VMSS["VM Scale Set (Ubuntu 22.04 · Zonas 1, 2 y 3)"]
                direction LR
                VM1["Instancia VMSS<br/>Sin IP pública · Identidad administrada<br/>cloud-init (sin secretos)"]
                VM2["Instancia VMSS<br/>Sin IP pública · Identidad administrada<br/>cloud-init (sin secretos)"]
            end

            Autoscale["Autoscale CPU: out ≥ 60% / in ≤ 25%<br/>Min 2 / Max 4 · Reparación automática"]
        end

        KV["Key Vault<br/>RBAC · Purge protection<br/>Firewall: snet-app + IP operador<br/>Secreto con expiración"]
        ST["Storage Account<br/>Sin llaves · Firewall activo"]
        LA[("Log Analytics<br/>Diagnostic settings: Key Vault (AuditEvent),<br/>Storage, Autoscale + Alertas por correo")]
    end

    GHA["GitHub Actions CI/CD<br/>fmt · validate · Checkov (bloqueante)"]

    Internet --> Pip --> LB
    LB -->|"Sonda /health y tráfico HTTP"| NSG
    NSG --> VMSS
    Autoscale -.->|"Escala / repara"| VMSS

    VMSS -->|"Identidad administrada (/secret-check)"| KV
    KV -.->|"Service Endpoint Microsoft.KeyVault"| VNet
    VMSS -->|"Firewall / acceso controlado"| ST

    KV -->|"AuditEvent"| LA
    ST -->|"Logs / métricas"| LA
    Autoscale -->|"Eventos de escalado"| LA

    GHA -.->|"Despliega y valida IaC"| RG

Endpoints de la app (`app/app.py`, solo librería estándar de Python; integra la app de `demo-escalamiento` y
la lectura del secreto de `demo-seguridad`):
`/` (instancia, zona y color) · `/api/info` (JSON) · `/work?ms=N` (consume ~N ms de CPU real: carga parad
administrada y devuelve **solo** longitud y SHA-256 truncado). Todas las respuestas llevan `X-Served-By`.

## Estructura del repositorio

| Ruta | Contenido |
|---|---|
| `infra/bootstrap/` | Storage Account endurecida para el estado remoto (se aplica una sola vez, estado local sin secretos) |
| `infra/` | Terraform principal: red, Key Vault, Storage, VMSS, LB, autoscale, monitoreo, política |
| `app/app.py` | Aplicación (se inyecta por cloud-init en base64) |
| `tests/` | `locustfile.py` (perfil escalonado 35 min, filas `BACKEND <instancia>` de la demo) y `locustfile_capacidad.py` (capacidad por instancia) |
| `scripts/` | Evidencias y pruebas de falla (`evidencias.sh`, `falla_logica.sh`, `falla_abrupta.sh`, `monitor.py`, `analizar_falla.py`, `graficar_p1.py`) |
| `.github/workflows/` | Pipeline `iac-seguridad.yml` |
| `evidencias/` | CSV/HTML de Locust, salidas de scripts y capturas |
| `informe/` | Informe del taller (fuente en Markdown) |

## Requisitos previos

Azure CLI con sesión iniciada, Terraform >= 1.6, Python 3, `pip install locust checkov matplotlib`,
llave SSH (`ssh-keygen -t rsa -b 4096`) y rol **Owner** sobre la suscripción (se crean roles y una política).

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az vm list-usage -l eastus2 -o table      # revise vCPU disponibles antes de fijar max_instances
curl -s ifconfig.me                       # su IP pública (en la red desde donde ejecutará Terraform)
```

## Cómo desplegar

```bash
# 0) Formato (obligatorio antes del primer commit: el pipeline hace fmt -check)
terraform fmt -recursive infra

# 1) Backend remoto (una sola vez)
cd infra/bootstrap
terraform init && terraform apply -var 'my_ip=["<SU_IP>"]'
terraform output -raw backend_config      # copie la salida a infra/backend.hcl

# 2) Plataforma
cd ..
cp terraform.tfvars.example terraform.tfvars   # edite my_ip (lista), alert_email
cp backend.hcl.example backend.hcl             # pegue los valores del paso 1
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan                         # ~8-10 min (incluye espera RBAC de 90 s)

terraform output app_url
curl $(terraform output -raw app_url)/secret-check
```

> Nota: si cambia `cloud-init` o `app.py`, el VMSS usa `upgrade_mode = "Manual"`: las instancias
> existentes no se actualizan solas. Reimagine con `az vmss update-instances -g <rg> -n <vmss> --instance-ids "*"`.

## Cómo destruir

```bash
cd infra && terraform destroy
cd bootstrap && terraform destroy -var 'my_ip=["<SU_IP>"]'
az group list --query "[?starts_with(name,'rg-caribeshop')].name" -o tsv   # debe quedar vacío
```

El Key Vault queda en soft-delete (protección de purga, sin costo).

## Variables requeridas

| Variable | Obligatoria | Descripción |
|---|---|---|
| `my_ip` | sí | **Lista** de IPv4 del operador, p. ej. `["1.2.3.4","5.6.7.8"]` (casa y universidad); firewall de Key Vault y Storage |
| `ssh_public_key_path` | no | Ruta de la llave SSH **pública** (`~/.ssh/id_rsa.pub`) |
| `alert_email` | sí | Correo para alertas y notificación de autoscale |
| `location`, `vm_size`, `zones` | no | `eastus2`, `Standard_B1s`, `["1","2","3"]` |
| `min_instances`, `max_instances` | no | `2`, `4` (para P1.1: `-var min_instances=1 -var max_instances=1`) |
| `scale_out_cpu`, `scale_in_cpu` | no | `60`, `25` (histéresis, igual que la demo) |
| `scale_out_window_min`, `scale_out_cooldown_min` | no | `5`, `3` |
| `scale_in_window_min`, `scale_in_cooldown_min` | no | `5`, `5` |
| `enable_tag_policy` | no | `false`; asigna además la política integrada de etiqueta obligatoria |

Ningún valor sensible va en el código: el secreto se genera con `random_password`, vive en Key Vault y la
app lo lee en tiempo de ejecución con su identidad administrada.

## Pruebas

```bash
# P1.1 capacidad por instancia (min=max=1) y P1.2/P1.3 perfil escalonado
locust -f tests/locustfile_capacidad.py --headless --host $(cd infra && terraform output -raw app_url) --csv evidencias/p1/capacidad --html evidencias/p1/capacidad.html
PEAK_USERS=40 locust -f tests/locustfile.py --headless --host <URL> --csv evidencias/p1/escalonada --csv-full-history --html evidencias/p1/escalonada.html

python3 scripts/graficar_p1.py evidencias/p1/escalonada_stats_history.csv   # instancias + RPS + p95 alineados

# P2 fallas (monitor en una terminal, Locust moderado en otra)
python3 scripts/monitor.py <URL> evidencias/p2/monitor_logica.csv
scripts/falla_logica.sh 1
scripts/falla_abrupta.sh 0

# Evidencias de texto S1-S6 / E1-E5 / P3
scripts/evidencias.sh
```

## Checklist de la línea base de seguridad

- [ ] `checkov -d infra --framework terraform` sin hallazgos fallidos; cada skip justificado (tabla de riesgos del informe)
- [ ] Ningún `terraform.tfstate`, `.tfvars` con datos reales ni secreto en el historial de Git
- [ ] Ninguna VM con IP pública; ningún puerto 22/3389 abierto a Internet
- [ ] Estado de Terraform en backend remoto (Storage sin llaves, firewall, versionado, TLS 1.2)
- [ ] Key Vault: RBAC, purge protection, firewall (subred + IP operador), secreto con expiración
- [ ] Identidad del VMSS con rol de solo lectura de secretos (`Key Vault Secrets User`)
- [ ] Egress filtrado (solo `AzureKeyVault`); Internet denegado
- [ ] Azure Policy con efecto Deny asignada por Terraform al grupo de recursos
- [ ] Diagnostic settings del Key Vault hacia Log Analytics + consulta KQL
- [ ] Pipeline bloqueante en PR (fmt, validate, Checkov terraform + secrets)
- [ ] Evidencias de scale-out, scale-in, falla lógica y falla abrupta con métricas
- [ ] Recursos destruidos (`terraform destroy`) y verificados en el portal
# CaribeShop
