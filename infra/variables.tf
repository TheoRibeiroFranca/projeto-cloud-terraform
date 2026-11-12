variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
  default     = "convcommerce"
}

variable "environment" {
  description = <<-EOT
    Nome do ambiente. Precisa ser diferente de "prod": IAM é global na conta,
    e as roles convcommerce-prod-* de Ohio já existem.
  EOT
  type        = string
  default     = "sp"
}

variable "region" {
  description = "Região AWS do ambiente."
  type        = string
  default     = "sa-east-1"
}

variable "az_count" {
  description = "Quantidade de zonas de disponibilidade usadas."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "Use pelo menos 2 zonas, para manter a alta disponibilidade."
  }
}

variable "ecs_instance_type" {
  description = "Tipo das instâncias EC2 do cluster ECS. Só zonas que o oferecem são usadas."
  type        = string
  default     = "t3.small"
}

variable "vpc_cidr" {
  description = "Faixa de IPs da VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "single_nat_gateway" {
  description = "true: um NAT para todas as zonas (mais barato). false: um NAT por zona."
  type        = bool
  default     = true
}
