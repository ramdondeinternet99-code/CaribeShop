output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "app_url" {
  description = "URL publica de la tienda (balanceador)."
  value       = "http://${azurerm_public_ip.lb.ip_address}"
}

output "app_fqdn_url" {
  description = "URL con el nombre DNS del balanceador."
  value       = "http://${azurerm_public_ip.lb.fqdn}"
}

output "storage_account_name" {
  value = azurerm_storage_account.data.name
}

output "autoscale_name" {
  value = azurerm_monitor_autoscale_setting.app.name
}

output "lb_public_ip" {
  value = azurerm_public_ip.lb.ip_address
}

output "lb_id" {
  value = azurerm_lb.main.id
}

output "vmss_name" {
  value = azurerm_linux_virtual_machine_scale_set.app.name
}

output "vmss_id" {
  value = azurerm_linux_virtual_machine_scale_set.app.id
}

output "vmss_principal_id" {
  description = "Identidad administrada del VMSS (para az role assignment list)."
  value       = azurerm_linux_virtual_machine_scale_set.app.identity[0].principal_id
}

output "autoscale_id" {
  value = azurerm_monitor_autoscale_setting.app.id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "secret_name" {
  value = var.secret_name
}

output "log_analytics_workspace_id" {
  description = "GUID del workspace (el que usa az monitor log-analytics query -w)."
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "policy_assignment" {
  value = azurerm_resource_group_policy_assignment.deny_public_blobs.name
}
