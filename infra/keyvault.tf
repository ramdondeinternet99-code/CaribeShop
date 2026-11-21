data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  #checkov:skip=CKV2_AZURE_32: Riesgo aceptado R2 - no se usa Private Endpoint por costo (~USD 8/mes); el acceso se restringe con firewall (subred con service endpoint + IP del operador) y RBAC. Mitigacion: Private Endpoint en produccion.
  name                          = "kv-${var.prefix}-${local.suffix}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
  tags                          = local.tags

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = var.my_ip
    virtual_network_subnet_ids = [azurerm_subnet.app.id]
  }
}

# Quien ejecuta Terraform administra secretos (Officer). La VM solo los lee (User).
resource "azurerm_role_assignment" "operator_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# La propagacion de RBAC no es instantanea: sin espera, crear el secreto da 403 intermitente.
resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.operator_kv_officer]
  create_duration = "90s"
}

resource "time_offset" "secret_expiry" {
  offset_days = 90
}

# El valor nunca aparece en el codigo: se genera y vive en Key Vault (y en el estado remoto cifrado; ver informe, pregunta 6).
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "#%*-_+"
}

resource "azurerm_key_vault_secret" "db_password" {
  name            = var.secret_name
  value           = random_password.db.result
  key_vault_id    = azurerm_key_vault.main.id
  content_type    = "password"
  expiration_date = time_offset.secret_expiry.rfc3339
  tags            = local.tags

  # El secreto se crea DESPUES de activar la auditoria para que SecretSet quede registrado.
  depends_on = [time_sleep.rbac_propagation, azurerm_monitor_diagnostic_setting.key_vault]
}

# S4: la identidad del VMSS solo puede LEER secretos de este vault.
resource "azurerm_role_assignment" "vmss_kv_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine_scale_set.app.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
