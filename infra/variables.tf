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

variable "rds_multi_az" {
  description = "true: banco com réplica em espera em outra zona (dobra o custo do RDS)."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "true: um NAT para todas as zonas (mais barato). false: um NAT por zona."
  type        = bool
  default     = true
}

variable "ecs_min_instances" {
  description = "Mínimo de instâncias no cluster."
  type        = number
  default     = 2
}

variable "ecs_max_instances" {
  # 6: no pico, as reservas de CPU somam ~7.200 unidades (chatbot com 512);
  # 4 t3.small dão 8.192, sem folga para o target de 90% do Capacity Provider.
  description = "Máximo de instâncias no cluster."
  type        = number
  default     = 6
}

variable "image_tag" {
  description = "Tag das imagens. Mudar este valor reconstrói as imagens e faz deploy da versão nova."
  type        = string
  default     = "2"
}

variable "build_images" {
  description = "true: o apply constrói e envia as imagens (requer Docker). false: as imagens já estão no ECR."
  type        = bool
  default     = true
}

variable "app_source_dir" {
  description = "Pasta que contém projeto-cloud-backend, projeto-cloud-chatbot e projeto-cloud-frontend."
  type        = string
  default     = "../.."
}

variable "alarm_emails" {
  description = "E-mails que recebem os alarmes e os avisos do orçamento (cada um precisa confirmar a inscrição dos alarmes)."
  type        = list(string)
  default     = []
}

variable "monthly_budget_usd" {
  description = "Limite mensal do orçamento do ambiente, em dólares."
  type        = number
  default     = 100
}

variable "admin_email" {
  description = "E-mail da conta de administrador da loja, criada no apply."
  type        = string
  default     = "admin@cirro.test"
}

variable "admin_name" {
  description = "Nome exibido da conta de administrador."
  type        = string
  default     = "Administrador"
}
