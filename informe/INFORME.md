---
title: "Taller integrador: plataforma segura, escalable y altamente disponible - Caso CaribeShop"
subtitle: "Infraestructura para TI · UTB"
author: "[COMPLETAR: integrantes del grupo]"
date: "[COMPLETAR: fecha]"
---

> **Cómo usar esta plantilla.** Todo lo marcado `[COMPLETAR: ...]` depende de SUS mediciones y capturas.
> Lo demás ya está redactado y alineado con el código del repositorio; revíselo y ajústelo a lo que realmente
> desplegaron. Máximo 12 páginas sin anexos. Borre este recuadro antes de exportar.

# 1. Arquitectura y decisiones de diseño

[COMPLETAR: insertar diagrama (exportar el de `README.md` a imagen o dibujarlo en draw.io). Debe mostrar IP pública, Load Balancer, VMSS en 2 zonas, NSG, Key Vault, Log Analytics, Azure Policy y pipeline.]

**Decisiones**

| Decisión | Alternativa descartada | Justificación |
|---|---|---|
| Load Balancer Standard (L4) | Application Gateway con WAF | Cumple S/E con menor costo (~USD 18/mes vs ~USD 180/mes). Se documenta como mejora de producción (HTTPS + WAF). |
| VMSS Uniform en zonas 1, 2 y 3 (`zone_balance = false`, mejor esfuerzo), min 2 | Una sola VM / un solo conjunto de disponibilidad | Tolera la caída de una zona (E1) y la falla de una instancia. |
| Sonda HTTP `/health` dedicada, 5 s × 2 fallos | Sonda TCP al puerto 80 | La TCP no detecta una app colgada pero con el puerto abierto; `/health` sí (probado en P2.1). Detección ≈ 10 s. |
| Autoscale por CPU con histéresis 60 % / 25 % (banda muerta de 35 puntos) | Umbrales iguales o cercanos | Evita *flapping*. Ventana de 5 min en ambas reglas; cooldown de 3 min al subir (reaccionar rápido) y 5 min al bajar (liberar con cautela). Valores heredados de `demo-escalamiento`. |
| Identidad administrada + Key Vault RBAC | Secreto en variables, cloud-init o repositorio | La credencial la emite la plataforma y expira sola; nada que robar del disco o del código (S3). |
| Rol `Key Vault Secrets User` al VMSS | `Contributor` o acceso por *access policies* | Solo lectura de secretos: mínimo privilegio (S4). |
| Firewall de Key Vault (subred + IP operador) | Acceso público abierto | Identidad y red son controles independientes (P3.1). |
| Egress denegado excepto `AzureKeyVault` | Salida libre a Internet | Un atacante con ejecución de código no puede exfiltrar (P3.2). Python viene en la imagen, por lo que no se necesita Internet al arrancar. |
| Azure Policy Deny a nivel de grupo de recursos | Solo escaneo en pipeline | Última línea de defensa aplicada a todos (S5, pregunta 5). |
| App en la imagen vía cloud-init (base64) | Configuración manual por SSH | Reproducible y sin pasos manuales (D3); no hay SSH. |
| Storage Account de aplicación sin llaves compartidas y con firewall (bloque de `demo-seguridad`) | Omitirla | Es parte de la arquitectura de referencia; sin llaves (solo Entra ID), con firewall por subred/IP, auditoría de blobs y versionado. La del estado de Terraform tiene el mismo endurecimiento (S1). |
| Trabajo de CPU calibrado en `/work` | Bucle por tiempo de reloj de la demo original | Con un bucle por tiempo, varios hilos terminan a la vez y la CPU no limita el rendimiento; con trabajo fijo el costo por petición es constante y la capacidad por instancia es medible (P1.1). |
| Región `eastus2`, B1s | Región más cercana a Colombia | Zonas disponibles, cuota y costo en Azure for Students. [AJUSTAR a su región.] |

# 2. Trazabilidad de requisitos

| ID | Archivo / recurso Terraform | Evidencia |
|---|---|---|
| S1 | `infra/providers.tf` (`backend "azurerm"`), `infra/bootstrap/main.tf`, `.gitignore` (sin `.tfvars`/estado) | `evidencias/auto/S1_backend_y_git.txt`; [COMPLETAR: captura del contenedor `tfstate` en el portal] |
| S2 | `infra/network.tf` (NSG, `default_outbound_access_enabled = false`); `compute.tf` (VMSS sin `public_ip_address`) | `evidencias/auto/S2_red_nsg.txt` (lista de IP públicas vacía) |
| S3 | `infra/keyvault.tf` (`azurerm_key_vault`, `azurerm_key_vault_secret`, expiración a 90 días); `app/app.py` (`/secret-check`); `cloud-init` (`leer-secreto.sh`) | `evidencias/auto/S3_secret_check.txt` y `S3_leer_secreto_runcommand.txt` (longitud y hash, no el valor) |
| S4 | `infra/keyvault.tf` (`azurerm_role_assignment.vmss_kv_reader`) | `evidencias/auto/S4_roles_vmss.txt` |
| S5 | `infra/policy.tf` (política `deny` sobre `allowBlobPublicAccess`) | `evidencias/auto/S5_policy_deny.txt` + [COMPLETAR: captura] |
| S6 | `infra/monitoring.tf` (`diag-keyvault`, categoría `AuditEvent`, tabla `AZKVAuditLogs`) | `evidencias/auto/S6_kql_secretos.txt` |
| E1 | `infra/compute.tf` (`zones`, `zone_balance`, `instances`) | `evidencias/auto/E1_instancias_zonas.txt` |
| E2 | `infra/compute.tf` (`azurerm_lb_probe.health`) | `evidencias/auto/E2_sonda.txt` + [COMPLETAR: captura de la métrica] |
| E3 | `infra/compute.tf` (`azurerm_monitor_autoscale_setting.app`, `ignore_changes = [instances]`) | `evidencias/auto/E3_autoscale*.txt`, historial de ejecución (portal), gráfico de P1 (`graficar_p1.py`) |
| E4 | `infra/compute.tf` (`automatic_instance_repair`) | [COMPLETAR: capturas antes/después con el ID de instancia reemplazada] |
| E5 | `infra/monitoring.tf` (`azurerm_monitor_metric_alert.probe` y `.cpu`, `azurerm_monitor_action_group.email`) | [COMPLETAR: captura del correo o del historial de alertas] |
| D1 | `.github/workflows/iac-seguridad.yml` | [COMPLETAR: enlaces a la ejecución exitosa y al PR que falla (con captura)] |
| D2 | `#checkov:skip` en `network.tf`, `keyvault.tf`, `compute.tf`, `storage.tf`, `bootstrap/main.tf` | Tabla de riesgos aceptados (sección 5) |
| D3 | `infra/cloud-init.yaml.tftpl` (servicio systemd + app + `leer-secreto.sh`), `app/app.py` | VMSS operativo sin ningún paso manual posterior al `apply` |

# 3. SLA compuesto estimado

Ruta crítica de la tienda: **IP pública Standard → Load Balancer Standard → VMSS en ≥ 2 zonas**.
Valores publicados por Microsoft (verificar en el documento oficial de SLA vigente antes de entregar):

| Componente | SLA |
|---|---|
| IP pública Standard | 99,99 % |
| Load Balancer Standard | 99,99 % |
| VMs en ≥ 2 zonas de disponibilidad | 99,99 % |
| Key Vault | 99,99 % |
| Log Analytics, Azure Monitor | fuera de la ruta crítica |

SLA compuesto de la ruta crítica (componentes en serie se multiplican):

$$0{,}9999 \times 0{,}9999 \times 0{,}9999 = 0{,}99970 \Rightarrow 99{,}97\ \%$$

Indisponibilidad máxima permitida: $43\,200\ \text{min} \times 0{,}0003 \approx 13\ \text{min/mes}$.

Si se considera el Key Vault dependencia dura (por ejemplo, si la tienda necesitara el secreto en cada petición):
$0{,}9999^4 = 99{,}96\ \% \Rightarrow \approx 17\ \text{min/mes}$. Hoy es dependencia blanda: solo `/secret-check` lo usa.

Límites del cálculo: es un SLA contractual (compensación financiera), no un compromiso de la aplicación; no cubre fallas de región, errores de configuración ni de la propia app. [COMPLETAR: contrastar con la disponibilidad medida en P2.]

# 4. Resultados de las pruebas

## P1. Carga y escalamiento

**P1.1 Capacidad de una instancia** (autoscale min = max = 1; `locustfile_capacidad.py`).

| Escalón (usuarios) | RPS | p95 (ms) | Fallos |
|---|---|---|---|
| [COMPLETAR] | | | |

Referencia de la demo: con 1 vCPU y `/work?ms=150`, ≈ 6-7 RPS por instancia (1 / 0,15 s). Capacidad máxima sostenible por instancia medida (último escalón con p95 < 1 s): **C = [COMPLETAR] RPS**. Con p95 < 500 ms: **C500 = [COMPLETAR] RPS**.
[COMPLETAR: gráfico RPS vs p95 y comentario sobre el punto de saturación (CPU de 1 vCPU, créditos de la serie B).]

**P1.2 y P1.3 Prueba escalonada** (35 min, `PEAK_USERS = [COMPLETAR]`, `TRABAJO_MS = 150`, CSV y HTML en `evidencias/p1/`).

[COMPLETAR: gráfico con tres paneles alineados en el tiempo: instancias (historial del autoscale / consulta `AutoscaleScaleActions`), RPS y p95 de Locust.]

| Métrica | Valor medido |
|---|---|
| Tiempo desde que la CPU supera 60 % hasta la primera instancia nueva en servicio | [COMPLETAR] |
| Instancias en el pico | [COMPLETAR] |
| Tiempo hasta el primer scale-in tras bajar la carga | [COMPLETAR] |
| p95 antes / durante / después del scale-out | [COMPLETAR] |

[COMPLETAR: análisis. Ejemplo de enfoque: mientras la instancia nueva arranca (cloud-init + sonda) el p95 sube; explicar el retardo = ventana de evaluación (5 min) + aprovisionamiento + calentamiento de la sonda; explicar por qué el scale-in es más lento que el scale-out (umbral de 25 % frente a 60 % y cooldown de 5 min frente a 3 min; la subida es rápida y la bajada gradual a propósito) y la banda muerta 25-60 % que evita el flapping.]

## P2. Pruebas de falla

| | Falla lógica (`/health` → 503) | Falla abrupta (instancia eliminada) |
|---|---|---|
| Carga durante la prueba | [COMPLETAR] usuarios / RPS | [COMPLETAR] |
| Tiempo hasta dejar de recibir tráfico | [COMPLETAR] s (esperado ≈ 10 s) | n/a |
| Peticiones en la ventana / fallidas | [COMPLETAR] / [COMPLETAR] | [COMPLETAR] / [COMPLETAR] |
| **% de error en la ventana** | [COMPLETAR] % | [COMPLETAR] % |
| Tiempo hasta recuperar la capacidad mínima | [COMPLETAR] (reparación automática ≥ 10 min por periodo de gracia) | [COMPLETAR] s |

[COMPLETAR: gráficos de `analizar_falla.py` y análisis. Puntos: la sonda detecta en ≈ 10 s, pero las conexiones ya asignadas a la instancia que muere de forma abrupta fallan hasta que la sonda la retira; con 2 instancias la capacidad queda reducida a la mitad hasta la recuperación; el autoscale restablece el mínimo configurado.]

## P3. Pruebas de seguridad

1. **Secreto desde red no autorizada.** [COMPLETAR: captura de Cloud Shell con `Forbidden / Client address is not authorized` usando un usuario que SÍ tiene el rol. Conclusión: identidad y red son controles independientes.]
2. **Egress.** `evidencias/auto/P3_2_egress.txt`: `internet: BLOQUEADO` y `keyvault: 401` (alcanzable, pide autenticación).
3. **Política Deny.** `evidencias/auto/S5_policy_deny.txt`: `RequestDisallowedByPolicy`. [COMPLETAR: captura.]

# 5. Riesgos aceptados (incluye cada `#checkov:skip`)

> Ajuste esta tabla a los `skip` que REALMENTE queden en su código tras correr `checkov -d infra`.

| ID | Control (Checkov) | Riesgo | Impacto | Mitigación / por qué se acepta |
|---|---|---|---|---|
| R1 | `CKV_AZURE_160` | HTTP/80 abierto a Internet | Tráfico sin cifrar | La tienda es pública por diseño. En producción: HTTPS + WAF (Application Gateway) |
| R2 | `CKV2_AZURE_32` | Key Vault sin Private Endpoint | Superficie pública con firewall | Costo ~USD 8/mes; mitigado con firewall (subred + IP) + RBAC + auditoría |
| R3 | `CKV_AZURE_97` | Sin *encryption at host* | Datos temporales del host sin cifrar | Requiere registrar la característica en la suscripción; discos cifrados en reposo con llaves de plataforma |
| R4 | `CKV_AZURE_95` | Sin parcheo automático de imagen | Vulnerabilidades del SO sin parchear | Reimagen periódica del VMSS; `upgrade_mode = Rolling` en producción |
| R5 | `CKV2_AZURE_1` (storage de la app) | Sin CMK | Llaves gestionadas por Microsoft | Cifrado de plataforma + doble cifrado; CMK en producción |
| R6 | `CKV2_AZURE_33` | Storage sin Private Endpoint | Superficie pública con firewall | Service endpoint + firewall + RBAC |
| R7 | `CKV_AZURE_59` | Acceso público de red habilitado (limitado por firewall) | Exposición si el firewall se relaja | Firewall por IP/subred; deshabilitarlo exige Private Endpoint |
| R8 | `CKV_AZURE_206` | ZRS en lugar de GZRS | Sin réplica entre regiones | ZRS da resiliencia zonal; GZRS en producción |
| R9 | `CKV_AZURE_33` | Sin registro de Queue | Ninguno: la cuenta no usa colas | No aplica |
| R9b | `CKV2_AZURE_21` (contenedor) | Check no reconoce el diagnóstico `StorageRead` | Falso positivo | Auditoría activa con `diag-blob` |
| B1-B6 | `CKV2_AZURE_1`, `CKV2_AZURE_33`, `CKV_AZURE_59`, `CKV_AZURE_206`, `CKV_AZURE_33`, `CKV2_AZURE_21` en `bootstrap/main.tf` | Mismos riesgos, aplicados a la Storage del estado de Terraform | Ver R5-R9 | Firewall por IP, sin llaves compartidas, versionado |
| R10 | (sin skip) | Valor del secreto en el estado de Terraform | Quien lea el estado ve el secreto | Backend remoto cifrado, privado, firewall, sin llaves compartidas; rotación (pregunta 6) |
| R11 | (sin skip) | Región única | Caída regional = caída total | Costo de multi-región (pregunta 3) |
| R12 | (sin skip) | VM serie B (créditos de CPU) | Throttling bajo carga sostenida | Entorno de taller; en producción serie D |

# 6. Estimación de costo mensual en producción

> Los precios son aproximados (lista, Linux, `eastus2`, 730 h/mes). **Reemplace con los valores de la Calculadora de precios de Azure y adjunte la exportación (Anexo E).**

Supuestos: instancias B2s, picos de 4 h/día que requieren 4 instancias, base de 2; 5 GB/mes de logs.

| Concepto | Sin autoscale (4 fijas 24/7) | Con autoscale (2 base + 2 en picos) |
|---|---|---|
| VMs B2s (≈ USD 30/mes c/u) | 4 × 30 = ≈ 121 | 2 × 30 + 2 × (30 × 4/24) = ≈ 70 |
| Discos Standard SSD 32 GB (≈ USD 2,4 c/u) | ≈ 10 | ≈ 5 |
| Load Balancer Standard | ≈ 18 | ≈ 18 |
| IP pública Standard | ≈ 4 | ≈ 4 |
| Log Analytics (5 GB) | ≈ 12 | ≈ 12 |
| Key Vault, alertas, autoscale | < 2 | < 2 |
| **Total aproximado (USD/mes)** | **≈ 167** | **≈ 111** |

El autoscale reduce ≈ 33 % porque se paga la capacidad pico solo durante las horas pico. [COMPLETAR: capturas/exportación de la calculadora y su escenario real.]

# 7. Preguntas de análisis

**1. ¿Cuántas instancias para 300 RPS con p95 < 500 ms? ¿Viable con la cuota? ¿Qué cambiaría?**
Con la capacidad medida C500 = [COMPLETAR] RPS por instancia y 30 % de holgura:
$N = \lceil 300 / (0{,}7 \cdot C_{500}) \rceil = [COMPLETAR]$ instancias (equivalente a [COMPLETAR] vCPU).
Cuota actual: [COMPLETAR: salida de `az vm list-usage`]. [COMPLETAR: viable / no viable.] Cambios: (a) más vCPU por instancia (serie D) y/o pedir aumento de cuota; (b) reducir el costo por petición (caché, optimizar `/work`, menor `TRABAJO_MS`); (c) CDN/Front Door para contenido cacheable; (d) subir `max_instances` y el escalón de scale-out a +2.

**2. Tiempo de reacción medido y ajuste para un pico a las 8:00 p. m.**
Reacción medida: [COMPLETAR] min (ventana de evaluación de 5 min + aprovisionamiento + cloud-init + sonda; la demo observó ~8-10 min desde el inicio de la carga). Un pico súbito supera ese retardo, por lo que se combina: (a) **perfil programado** que suba el mínimo (p. ej. a [COMPLETAR] instancias) a las 7:45 p. m. y lo baje después; (b) **autoscale predictivo** (modo *forecast only* primero, necesita historial de CPU de varios días) para anticipar patrones diarios; (c) scale-out de +2 con ventana más corta (p. ej. 3 min) para picos; (d) mantener el scale-in conservador.

**3. ¿Qué componente es ahora el punto único de falla? ¿Cuánto costaría eliminarlo?**
La **región** (todo vive en una sola): una falla regional detiene la tienda; la IP, el LB y el VMSS ya son zonales. El Key Vault es dependencia blanda (solo `/secret-check`). Eliminarlo implica una segunda región activa-pasiva o activa-activa con Azure Front Door o Traffic Manager: aproximadamente **duplicar el costo de cómputo y LB (≈ + USD [COMPLETAR])** más el balanceador global (Front Door Standard ≈ USD 35/mes base + tráfico, verificar en la calculadora) y un segundo Key Vault.

**4. Si un atacante ejecuta código en una instancia, ¿qué puede y qué no puede hacer?**
*Capa de aplicación:* el servicio corre con `DynamicUser`, sin privilegios y con `NoNewPrivileges`/`ProtectSystem`. *Red:* sin IP pública, SSH/RDP denegados; el egress solo permite `AzureKeyVault`, así que **no puede exfiltrar** a un servidor propio ni descargar herramientas. *Identidad:* **sí puede** pedir un token a IMDS y leer los secretos de ese Key Vault (rol `Secrets User`), por eso el vault solo guarda lo necesario y se audita (KQL); **no puede** escribir secretos, tocar otros recursos ni escalar privilegios en Azure (el rol no existe fuera de ese alcance). *Cómputo:* puede saturar la CPU de la instancia; el autoscale y la reparación la compensan. *Gobierno:* Azure Policy impide que cree Storage público. *Detección:* cada lectura queda en Log Analytics y la alerta de sonda avisa de anomalías.

**5. ¿Por qué el escaneo en el pipeline no sustituye a Azure Policy, ni viceversa?**
El escaneo (Checkov) es **preventivo y temprano** pero solo ve el código que pasa por el pipeline: se evita con el portal, la CLI u otro repositorio, y no ve la deriva posterior. Azure Policy es la **última línea**: se aplica en el plano de control a todos, incluso a un administrador apurado, pero detecta tarde (cuando alguien ya intenta desplegar), solo cubre lo que se escribió como regla y da feedback menos claro al desarrollador. Se complementan: el pipeline da retroalimentación rápida en el PR, la política garantiza el estado real del entorno.

**6. El estado de Terraform contiene secretos. ¿Cómo lo protegieron y qué pasaría si se filtrara?**
Se guarda en un backend remoto `azurerm` en una Storage Account con cifrado, versionado, TLS 1.2, sin acceso público, **sin llaves compartidas** (solo Entra ID), firewall por IP y rol de datos para el operador; está en `.gitignore` y no hay estado en el historial de Git. Aun así, `sensitive = true` solo oculta la salida en consola: el valor del secreto está en texto plano dentro del estado. Si se filtrara: se compromete el secreto generado (la contraseña de base de datos simulada) y se revela la topología; la respuesta es **rotar** el secreto (`terraform apply -replace=random_password.db`), revisar el acceso con los logs de la Storage y, si hubo exposición, rotar también cualquier credencial que Terraform conozca. Mejora de producción: no dejar que Terraform genere el valor (crearlo fuera de banda o con `ephemeral` / `write_only` según versión del provider) y CMK + Private Endpoint.

# Anexos

- **A.** Salida completa de `checkov -d infra --framework terraform --compact` (0 fallos, N skips).
- **B.** Capturas: portal (Instancias y zonas, Autoscale → historial de ejecución, alertas/correo, política, Key Vault → red).
- **C.** Resultados de KQL (`evidencias/auto/S6_kql_secretos.txt`, autoscale).
- **D.** Reportes de Locust (`evidencias/p1/*.html`, CSV) y gráficos de falla (`evidencias/p2/*.png`).
- **E.** Exportación de la Calculadora de precios de Azure.
- **F.** Enlaces: repositorio, PR fallido, PR corregido, ejecución exitosa del workflow, video de YouTube.
