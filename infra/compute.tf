resource "azurerm_public_ip" "lb" {
  name                = "pip-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  domain_name_label   = "${var.prefix}-${local.suffix}"
  tags                = local.tags
}

resource "azurerm_lb" "main" {
  name                = "lb-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

resource "azurerm_lb_backend_address_pool" "app" {
  name            = "pool-app"
  loadbalancer_id = azurerm_lb.main.id
}

# E2: sonda sobre un endpoint dedicado (/health). Deteccion: 5 s x 2 fallos = ~10 s.
resource "azurerm_lb_probe" "health" {
  name                = "probe-health"
  loadbalancer_id     = azurerm_lb.main.id
  protocol            = "Http"
  port                = 80
  request_path        = "/health"
  interval_in_seconds = 5
  probe_threshold     = 2
}

resource "azurerm_lb_rule" "http" {
  name                           = "http"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app.id]
  probe_id                       = azurerm_lb_probe.health.id
  idle_timeout_in_minutes        = 4

  # Las instancias no necesitan salir a Internet: sin SNAT de salida.
  disable_outbound_snat = true
}

# D3: la VM se configura sola al arrancar (cloud-init). La app va embebida en base64
# y solo se inyecta el NOMBRE del vault, nunca un secreto.
locals {
  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    app_b64        = filebase64("${path.module}/../app/app.py")
    key_vault_name = azurerm_key_vault.main.name
    secret_name    = var.secret_name
  })
}

resource "azurerm_linux_virtual_machine_scale_set" "app" {
  #checkov:skip=CKV_AZURE_97: Riesgo aceptado R3 - encryption-at-host requiere registrar la caracteristica Microsoft.Compute/EncryptionAtHost en la suscripcion; los discos ya estan cifrados en reposo con llaves de plataforma. Mitigacion: activar en produccion.
  #checkov:skip=CKV_AZURE_95: Riesgo aceptado R4 - sin parcheo automatico de imagen (requiere upgrade_mode Rolling). Mitigacion: reimagen periodica del VMSS en produccion.
  name                            = "vmss-${var.prefix}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  sku                             = var.vm_size
  instances                       = var.min_instances
  zones                           = var.zones
  zone_balance                    = false # mejor esfuerzo (como la demo): no bloquea si una zona no tiene capacidad
  overprovision                   = false
  upgrade_mode                    = "Manual"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  health_probe_id                 = azurerm_lb_probe.health.id
  custom_data                     = base64encode(local.cloud_init)
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  tags                            = local.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "StandardSSD_LRS"
    caching              = "ReadWrite"
  }

  # S3/S4: identidad administrada del VMSS (sin credenciales).
  identity {
    type = "SystemAssigned"
  }

  network_interface {
    name    = "nic-app"
    primary = true

    ip_configuration {
      name                                   = "ipconfig"
      primary                                = true
      subnet_id                              = azurerm_subnet.app.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.app.id]
    }
  }

  # E4: reparacion automatica de instancias no sanas (segun la sonda del LB).
  automatic_instance_repair {
    enabled      = true
    grace_period = "PT10M"
  }

  boot_diagnostics {}

  # El autoscale es dueno de la cantidad de instancias (E3).
  lifecycle {
    ignore_changes = [instances]
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.app,
    azurerm_lb_rule.http,
  ]
}

# E3: autoscale con histeresis (60 % out / 25 % in) y cooldowns distintos (3 min out / 5 min in).
resource "azurerm_monitor_autoscale_setting" "app" {
  name                = "autoscale-${var.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.app.id
  tags                = local.tags

  profile {
    name = "cpu-default"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    # Scale-out: cooldown corto (3 min): reaccionar rapido a la demanda.
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT${var.scale_out_window_min}M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.scale_out_cpu
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.scale_out_cooldown_min}M"
      }
    }

    # Scale-in: umbral mucho menor (banda muerta 25-60 %) y cooldown mas largo: evita el "aleteo" (flapping).
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT${var.scale_in_window_min}M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.scale_in_cpu
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT${var.scale_in_cooldown_min}M"
      }
    }
  }

  notification {
    email {
      send_to_subscription_administrator = false
      custom_emails                      = [var.alert_email]
    }
  }

  lifecycle {
    precondition {
      condition     = var.scale_in_cpu < var.scale_out_cpu
      error_message = "Histeresis: scale_in_cpu debe ser menor que scale_out_cpu."
    }
    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances debe ser >= min_instances."
    }
  }
}
