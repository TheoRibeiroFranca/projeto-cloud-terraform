variable "name_prefix" {
  description = "Prefixo dos nomes dos recursos (ex.: convcommerce-sp)."
  type        = string
}

variable "vpc_cidr" {
  description = "Faixa de IPs da VPC."
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr precisa ser um CIDR válido, como 10.10.0.0/16."
  }
}

variable "azs" {
  description = "Zonas de disponibilidade. Uma subnet pública e uma privada em cada."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Use pelo menos 2 zonas de disponibilidade."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    true: um NAT Gateway para todas as zonas (mais barato; se a zona dele cair,
    as subnets privadas perdem a saída para a internet).
    false: um NAT por zona (alta disponibilidade, custo multiplicado).
  EOT
  type        = bool
  default     = true
}
