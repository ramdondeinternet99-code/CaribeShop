# S5: ultima linea de defensa. Aunque alguien se salte el pipeline (portal, CLI),
# Azure rechaza crear Storage con acceso publico a blobs dentro de este grupo de recursos.
# Regla tomada de demo-seguridad/03-policy (probada). Se asigna al grupo de recursos de la plataforma.
resource "azurerm_policy_definition" "deny_public_blobs" {
  name         = "deny-blobs-publicos-${var.prefix}"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "CaribeShop - Denegar Storage con acceso publico a blobs"
  description  = "Rechaza cualquier Storage Account cuyo allowBlobPublicAccess no sea false."

  metadata = jsonencode({ category = "Storage", version = "1.0.0" })

  policy_rule = jsonencode({
    "if" = {
      allOf = [
        { field = "type", equals = "Microsoft.Storage/storageAccounts" },
        {
          field     = "Microsoft.Storage/storageAccounts/allowBlobPublicAccess"
          notEquals = false
        }
      ]
    }
    "then" = { effect = "deny" }
  })
}

resource "azurerm_resource_group_policy_assignment" "deny_public_blobs" {
  name                 = "deny-blobs-publicos"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = azurerm_policy_definition.deny_public_blobs.id
  display_name         = "CaribeShop - No blobs publicos"
}

# Politica INTEGRADA opcional (variable enable_tag_policy): exigir la etiqueta "responsable".
# Se deja DESACTIVADA por defecto: aplicada al mismo grupo que el VMSS podria rechazar
# recursos que la plataforma crea sin etiquetas (p. ej. instancias creadas por el autoscale).
data "azurerm_policy_definition" "require_tag" {
  count        = var.enable_tag_policy ? 1 : 0
  display_name = "Require a tag on resources"
}

resource "azurerm_resource_group_policy_assignment" "require_tag" {
  count                = var.enable_tag_policy ? 1 : 0
  name                 = "requiere-tag-responsable"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = data.azurerm_policy_definition.require_tag[0].id
  display_name         = "Exigir etiqueta 'responsable'"

  parameters = jsonencode({
    tagName = { value = "responsable" }
  })
}
