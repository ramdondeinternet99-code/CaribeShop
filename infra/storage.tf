# Almacenamiento de datos de la aplicacion (arquitectura de referencia). Reutiliza el
# bloque endurecido de demo-seguridad/02-seguro. Riesgos ACEPTADOS (cada skip lleva su justificacion):
resource "azurerm_storage_account" "data" {
  #checkov:skip=CKV2_AZURE_1: Riesgo aceptado R5 - sin llaves administradas por el cliente (CMK); se usa cifrado de plataforma + doble cifrado. Mitigacion: CMK en produccion.
  #checkov:skip=CKV2_AZURE_33: Riesgo aceptado R6 - sin Private Endpoint por costo; se usa service endpoint + firewall.
  #checkov:skip=CKV_AZURE_59: Riesgo aceptado R7 - el acceso publico queda limitado por firewall (IP del operador + subred); deshabilitarlo exige Private Endpoint.
  #checkov:skip=CKV_AZURE_206: Riesgo aceptado R8 - ZRS (resiliencia zonal) es suficiente; produccion evaluaria GZRS.
  #checkov:skip=CKV_AZURE_33: Riesgo aceptado R9 - no se usa el servicio Queue en esta cuenta.
  name                     = "st${var.prefix}${local.suffix}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  tags                     = local.tags

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true

  sas_policy {
    expiration_period = "00.02:00:00"
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = var.my_ip
    virtual_network_subnet_ids = [azurerm_subnet.app.id]
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}

# Sin llaves compartidas, Terraform necesita un rol de datos para crear contenedores.
resource "azurerm_role_assignment" "operator_blob" {
  scope                = azurerm_storage_account.data.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "rbac_storage" {
  depends_on      = [azurerm_role_assignment.operator_blob]
  create_duration = "90s"
}

resource "azurerm_storage_container" "data" {
  #checkov:skip=CKV2_AZURE_21: El registro de lecturas se hace con diagnostic setting StorageRead; el check solo reconoce Storage Analytics clasico.
  name                  = "datos-clientes"
  storage_account_id    = azurerm_storage_account.data.id
  container_access_type = "private"

  depends_on = [time_sleep.rbac_storage]
}

# Auditoria de lecturas, escrituras y borrados de blobs.
resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.data.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}
