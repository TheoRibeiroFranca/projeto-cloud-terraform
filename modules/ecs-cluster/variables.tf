variable "name_prefix" {
  description = "Prefixo dos nomes; também é o nome do cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas onde as instâncias sobem."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group das instâncias ECS."
  type        = string
}

variable "instance_profile_name" {
  description = "Instance profile com a role das instâncias."
  type        = string
}

variable "instance_type" {
  description = "Tipo das instâncias."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Disco de cada instância, em GB (imagens e camadas dos containers)."
  type        = number
  default     = 30
}

variable "min_size" {
  description = "Mínimo de instâncias. 2 mantém uma instância por zona."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Máximo de instâncias."
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Instâncias na criação. Depois, quem decide é o Capacity Provider."
  type        = number
  default     = 2
}

variable "target_capacity" {
  description = <<-EOT
    Ocupação desejada do cluster, em %. 90 deixa uma folga pequena para uma task
    nova subir sem esperar instância; 100 seria nenhuma folga.
  EOT
  type        = number
  default     = 90
}

variable "instance_warmup_seconds" {
  description = "Tempo até uma instância nova contar nas métricas de capacidade."
  type        = number
  default     = 180
}

variable "container_insights" {
  description = "Nível do Container Insights: enhanced, enabled ou disabled."
  type        = string
  default     = "enhanced"
}
