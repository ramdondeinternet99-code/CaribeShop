# Plan de trabajo 

## Días 1-2: repositorio, backend y pipeline  → rúbrica *IaC y estado (10 %)*, *DevSecOps (10 %)*

1. Instalar herramientas (ver README) y `az login`.
2. `terraform fmt -recursive infra` y `terraform -chdir=infra/bootstrap init && terraform -chdir=infra/bootstrap validate`.
3. Crear repositorio **público** en GitHub (para que Code scanning sea gratuito) y subir este proyecto (`git init`, `git push`).
4. Ejecutar el bootstrap (backend remoto) y llenar `infra/backend.hcl` y `infra/terraform.tfvars` (**no se suben a Git**). `my_ip` es una **lista**: incluya la IP de cada red desde la que va a ejecutar Terraform (casa y universidad: `curl -s ifconfig.me` en cada una).
5. Correr `checkov -d infra --framework terraform --compact` localmente. **Ajustar:** por cada hallazgo restante, corregir el código o agregar `#checkov:skip=ID: justificación` y registrarlo en la tabla de riesgos del informe. Eliminar los `skip` que ya no hagan falta.

## Días 3-8: desplegar y endurecer  → *Red, Identidad, Gobierno, Escalamiento, Alta disponibilidad*

6. `terraform -chdir=infra init -backend-config=backend.hcl && terraform -chdir=infra apply`.
7. Si falla: revisar la tabla de problemas abajo.
8. `curl $(terraform -chdir=infra output -raw app_url)/secret-check` debe devolver `leido: true`.
9. Confirmar que llegó el correo de suscripción del grupo de acción (revisar spam y aceptar si lo pide).

## D1 - PR que falla y su corrección (obligatorio: 2 PR cerrados)

```bash
git checkout -b prueba-falla-seguridad
# En infra/network.tf agregue una regla que abra SSH a Internet (CKV_AZURE_10), por ejemplo:
#   destination_port_range = "22" y source_address_prefix = "*" con access = "Allow"
git commit -am "prueba: SSH abierto (debe fallar)" && git push -u origin prueba-falla-seguridad
# Abra el PR -> Checkov falla (captura). Luego corrija en la misma rama, el pipeline pasa, haga merge.
```

Captura del PR rojo, del PR verde y copie ambos enlaces al informe. Nota: configure *Branch protection* en `main` exigiendo los checks para que el bloqueo sea real.

## Días 9-10: pruebas y evidencias  → *Escalamiento (15 %)*, *Alta disponibilidad (15 %)*

| Prueba | Pasos |
|---|---|
| P1.1 | `terraform apply -var min_instances=1 -var max_instances=1` → Locust `locustfile_capacidad.py` hasta p95 de `/work` > 1 s → anotar RPS del escalón anterior (referencia de la demo: ≈ 6-7 RPS por instancia) → volver a `apply` sin esos `-var`. |
| P1.2/1.3 | `PEAK_USERS` tal que la demanda supere la capacidad de 2 instancias (≈ 1 RPS por usuario: con C ≈ 6,5 RPS, 2 instancias aguantan ≈ 13 usuarios; use ≈ 30-40 para forzar 4). Correr `locustfile.py` 35 min con `--csv --csv-full-history --html`, luego `scripts/graficar_p1.py` y capturar el **historial de ejecución** del autoscale en el portal (hora UTC vs. local). La fila Aggregated de Locust duplica el RPS por las filas BACKEND: use `/work` + `/api/info`. |
| P2.1 | `monitor.py` en una terminal, Locust moderado (~50 % de la capacidad de 2 instancias), `scripts/falla_logica.sh 1`, esperar 2 min, `analizar_falla.py`. Dejar >10-15 min para ver la reparación automática (E4) o llamar `restaurar_salud.sh`. |
| P2.2 | Igual con `scripts/falla_abrupta.sh 0`. |
| P3 | `scripts/evidencias.sh` + captura desde **Azure Cloud Shell** del `Forbidden` al leer el secreto. |
| E5 | Provocar la alerta: P2.1 baja `DipAvailability` por debajo de 100 %. Capturar correo. |

Antes de P1: `az vm list-usage -l eastus2 -o table`. Supervise las pruebas (créditos de CPU de la serie B).

## Días 11-14: informe, video, destrucción  → *Informe, análisis y video (15 %)*

- Completar `informe/INFORME.md` (todo `[COMPLETAR]`), exportarlo a PDF (≤ 12 páginas sin anexos):
  `pandoc informe/INFORME.md -o informe/Informe.pdf` (necesita LaTeX) o pegarlo en Word y exportar.
- Calcular costos en la Calculadora de precios de Azure y guardar la exportación.
- **Video 6-8 min** (llamada de Teams grabada con todos hablando → YouTube público): 1) arquitectura (1 min), 2) despliegue ya hecho + `secret-check` (1 min), 3) Locust y aparición de una instancia nueva (2-3 min), 4) una prueba de falla (1-2 min), 5) política Deny / KQL (1 min). Repartan los bloques entre todos.
- `terraform destroy` (infra y luego bootstrap) y verificar en el portal que no quedan grupos `rg-caribeshop*`.

## Pipeline: PR que falla y plan con OIDC (opcional)

- Para el PR que falla puede tomar un anti-patrón de `01-inseguro` de la demo (SSH abierto: `CKV_AZURE_10`, TLS 1.0: `CKV_AZURE_44`). No copie `01-inseguro` al repo (tiene secretos falsos que activarían el escaneo de secretos).
- Plan con OIDC: siga el **Apéndice A** de la guía de seguridad con el nombre de SU repositorio, agregue también la credencial federada del sujeto `...:pull_request`, cree las variables del repo `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` y active el job con la variable `ENABLE_PLAN=true`. Si no tienen permisos en Entra ID, omítanlo: la rúbrica exige fmt, validate y Checkov bloqueante.

## Problemas probables

| Síntoma | Causa | Solución |
|---|---|---|
| `terraform validate`: argumento desconocido (`probe_threshold`, `rbac_authorization_enabled`, `default_outbound_access_enabled`, `secure_boot_enabled`) | Versión del provider distinta | Subir a `azurerm ~> 4.20`+ o usar el nombre vigente según la documentación del provider |
| 403 al crear el secreto o contenedor | `my_ip` distinta de la IP real o RBAC sin propagar | `curl -s ifconfig.me` en la misma red y repetir `apply` |
| `SkuNotAvailable` / `QuotaExceeded` | Tamaño o cuota por región/zona | Cambiar `vm_size`, `zones` o `location`; reducir `max_instances` |
| Error de Trusted Launch | Tamaño no lo soporta | Poner `secure_boot_enabled`/`vtpm_enabled` en `false` |
| `RequestDisallowedByPolicy` al crear la VM | Política de la suscripción de estudiante | Cambiar región o tamaño |
| `/secret-check` devuelve 502 con 403 | Rol de la VM no propagado | Esperar unos minutos |
| El autoscale no agrega instancias | Ventana de 5 min no cumplida, o cuota agotada | Historial de ejecución y `az monitor activity-log list` (errores de cuota); CPU no sube: créditos B agotados o métrica con 1-3 min de retraso |
| Locust muestra RPS duplicado en Aggregated | Filas sintéticas BACKEND | Usar las filas `/work` y `/api/info` (o `graficar_p1.py`) |
| El VMSS queda sin salud | Falla de cloud-init | `az vmss run-command invoke ... --scripts "journalctl -u caribeshop -n 50"` y `cloud-init status` |
| KQL sin filas | Latencia de diagnósticos | Esperar 10-15 min y repetir la lectura del secreto |
