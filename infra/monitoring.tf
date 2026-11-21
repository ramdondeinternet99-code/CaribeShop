resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.prefix}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# S6: auditoria del Key Vault (quien leyo el secreto). Tabla dedicada AZKVAuditLogs.
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                           = "diag-keyvault"
  target_resource_id             = azurerm_key_vault.main.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AuditEvent"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Evidencia de E3: cada evaluacion y accion del autoscale queda en Log Analytics.
resource "azurerm_monitor_diagnostic_setting" "autoscale" {
  name                       = "diag-autoscale"
  target_resource_id         = azurerm_monitor_autoscale_setting.app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AutoscaleEvaluations"
  }

  enabled_log {
    category = "AutoscaleScaleActions"
  }
}

# E5: alertas con notificacion por correo.
resource "azurerm_monitor_action_group" "email" {
  name                = "ag-${var.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "caribeshop"
  tags                = local.tags

  email_receiver {
    name                    = "equipo"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# Sonda del balanceador por debajo de 100 % = alguna instancia no sana.
resource "azurerm_monitor_metric_alert" "probe" {
  name                = "alerta-sonda-lb-${var.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_lb.main.id]
  description         = "Health Probe Status (DipAvailability) por debajo de 100 %: hay instancias no sanas."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Network/loadBalancers"
    metric_name      = "DipAvailability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}

# CPU sostenida alta aun con autoscale: senal de que max_instances es insuficiente.
resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "alerta-cpu-sostenida-${var.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.app.id]
  description         = "CPU promedio por encima de 85 % durante 15 minutos."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}
