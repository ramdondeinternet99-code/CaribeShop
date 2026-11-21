variable "location" {
  description = "Region de Azure (debe tener zonas de disponibilidad para E1)."
  type        = string
  default     = "eastus2"
}

variable "prefix" {
  description = "Prefijo para nombrar recursos (minusculas, max 10 caracteres)."
  type        = string
  default     = "caribeshop"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.prefix))
    error_message = "prefix: 3-10 caracteres, solo minusculas y numeros."
  }
}

variable "owner" {
  description = "Valor de la etiqueta 'responsable'."
  type        = string
  default     = "grupo-caribeshop"
}

variable "my_ip" {
  description = "IPs publicas del operador (curl -s ifconfig.me), una por red desde la que ejecutara Terraform (casa, universidad). Van al firewall de Key Vault y Storage."
  type        = list(string)

  validation {
    condition     = length(var.my_ip) > 0 && alltrue([for ip in var.my_ip : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip))])
    error_message = "my_ip debe ser una lista de IPv4 sin mascara, por ejemplo [\"203.0.113.10\"]."
  }
}

variable "ssh_public_key_path" {
  description = "Ruta a la llave SSH PUBLICA (la VM no acepta contrasena y el puerto 22 no esta expuesto)."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "alert_email" {
  description = "Correo que recibe las alertas de Azure Monitor (E5)."
  type        = string
}

variable "vm_size" {
  description = "Tamano de las instancias. Revise cuota con: az vm list-usage -l <region> -o table"
  type        = string
  default     = "Standard_B1s"
}

variable "zones" {
  description = "Zonas de disponibilidad del VMSS (minimo 2 para E1)."
  type        = list(string)
  default     = ["1", "2", "3"]

  validation {
    condition     = length(var.zones) >= 2
    error_message = "E1 exige al menos 2 zonas de disponibilidad."
  }
}

variable "min_instances" {
  description = "Minimo del autoscale (E1 exige >= 2). Para P1.1 se baja temporalmente a 1."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1
    error_message = "min_instances debe ser >= 1."
  }
}

variable "max_instances" {
  description = "Maximo del autoscale. No exceda su cuota de vCPU por region."
  type        = number
  default     = 4
}

variable "scale_out_cpu" {
  description = "Scale-out: CPU promedio (%) por encima de la cual se agrega 1 instancia."
  type        = number
  default     = 60
}

variable "scale_in_cpu" {
  description = "Scale-in: CPU promedio (%) por debajo de la cual se quita 1 instancia (histeresis: debe ser menor que scale_out_cpu)."
  type        = number
  default     = 25
}

variable "scale_out_window_min" {
  description = "Ventana (min) de evaluacion del scale-out."
  type        = number
  default     = 5
}

variable "scale_out_cooldown_min" {
  description = "Enfriamiento (min) tras un scale-out."
  type        = number
  default     = 3
}

variable "scale_in_window_min" {
  description = "Ventana (min) de evaluacion del scale-in."
  type        = number
  default     = 5
}

variable "scale_in_cooldown_min" {
  description = "Enfriamiento (min) tras un scale-in."
  type        = number
  default     = 5
}


variable "secret_name" {
  description = "Nombre del secreto en Key Vault (el valor se genera aleatoriamente)."
  type        = string
  default     = "app-db-password"
}

variable "enable_tag_policy" {
  description = "Asigna ademas la politica integrada 'Require a tag on resources' (responsable). Desactivada por defecto: puede rechazar recursos creados por la plataforma sin etiquetas."
  type        = bool
  default     = false
}
