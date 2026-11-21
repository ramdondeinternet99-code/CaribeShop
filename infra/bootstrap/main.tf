terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "azurerm" {
  storage_use_azuread = true

  features {}
}

variable "location" {
  description = "Region de Azure."
  type        = string
  default     = "eastus2"
}

variable "my_ip" {
  description = "IPs publicas del operador: unicas que pueden alcanzar el estado."
  type        = list(string)

  validation {
    condition     = length(var.my_ip) > 0 && alltrue([for ip in var.my_ip : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip))])
    error_message = "my_ip debe ser una lista de IPv4 sin mascara."
  }
}

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_resource_group" "state" {
  name     = "rg-caribeshop-tfstate"
  location = var.location

  tags = {
    proyecto = "caribeshop"
    uso      = "estado-terraform"
  }
}

# El estado contiene secretos (p. ej. el valor del secreto generado): se protege con
# cifrado, versionado, sin acceso publico, sin llaves compartidas y firewall.
resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV2_AZURE_1: Riesgo aceptado B1 - cifrado con llaves de plataforma en vez de CMK (costo/complejidad). Mitigacion: CMK en produccion.
  #checkov:skip=CKV2_AZURE_33: Riesgo aceptado B2 - sin Private Endpoint por costo; acceso limitado por firewall (IP del operador) y RBAC de Entra ID.
  #checkov:skip=CKV_AZURE_59: Riesgo aceptado B3 - acceso publico limitado por firewall (IP del operador); deshabilitarlo exige Private Endpoint.
  #checkov:skip=CKV_AZURE_206: Riesgo aceptado B4 - ZRS suficiente para el estado; produccion evaluaria GZRS.
  #checkov:skip=CKV_AZURE_33: Riesgo aceptado B5 - la cuenta no usa colas; el registro de Queue no aplica.
  name                            = "stcaribeshop${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  tags                            = azurerm_resource_group.state.tags

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = var.my_ip
  }
}

resource "azurerm_role_assignment" "operator_blob_owner" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.operator_blob_owner]
  create_duration = "90s"
}

resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21: Riesgo aceptado B6 - sin diagnostico de lectura de blobs a Log Analytics (costo). Mitigacion: Activity Log y versionado del blob.
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  depends_on = [time_sleep.rbac_propagation]
}

output "backend_config" {
  description = "Copie estos valores a infra/backend.hcl"
  value = <<-EOT
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    key                  = "caribeshop.tfstate"
    use_azuread_auth     = true
  EOT
}
