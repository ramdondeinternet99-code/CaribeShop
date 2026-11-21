resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result

  tags = {
    proyecto    = "caribeshop"
    responsable = var.owner
    entorno     = "taller"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = local.tags
}
