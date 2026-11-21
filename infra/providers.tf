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

  # S1: estado en backend remoto (Storage Account creada por infra/bootstrap).
  # Configuracion parcial: los valores NO secretos van en backend.hcl
  # (terraform init -backend-config=backend.hcl). Autenticacion por Entra ID.
  backend "azurerm" {}
}

# Sin credenciales en el codigo: la autenticacion sale de `az login`
# (local) o de OIDC (pipeline). La suscripcion se toma de ARM_SUBSCRIPTION_ID.
provider "azurerm" {
  storage_use_azuread = true

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
