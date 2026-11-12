variable "name_prefix" {
  description = "Prefixo dos nomes (ex.: convcommerce-sp)."
  type        = string
}

variable "region" {
  description = "Região (para os gráficos do dashboard)."
  type        = string
}

variable "alarm_emails" {
  description = <<-EOT
    E-mails que recebem os alarmes. Cada pessoa recebe um e-mail da AWS e
    precisa clicar em "Confirm subscription" antes de começar a receber.
  EOT
  type        = list(string)
  default     = []
}

variable "app_env" {
  description = "Valor da dimensão env nas métricas da aplicação (APP_ENV)."
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "Cluster ECS."
  type        = string
}

variable "capacity_provider_name" {
  description = "Capacity Provider do cluster."
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling Group do cluster."
  type        = string
}

variable "ecs_services" {
  description = "Serviços ECS: nome curto -> nome no ECS."
  type        = map(string)
}

variable "alb_public_arn_suffix" {
  description = "Sufixo do ARN do ALB público."
  type        = string
}

variable "alb_internal_arn_suffix" {
  description = "Sufixo do ARN do ALB interno."
  type        = string
}

variable "target_groups" {
  description = "Target groups: nome -> { arn_suffix, internal }."
  type = map(object({
    arn_suffix = string
    internal   = bool
  }))
}

variable "orders_queue_name" {
  description = "Fila de pedidos."
  type        = string
}

variable "orders_dlq_name" {
  description = "DLQ da fila de pedidos."
  type        = string
}

variable "rds_identifier" {
  description = "Identificador da instância RDS."
  type        = string
}

variable "alb_p95_latency_seconds" {
  description = <<-EOT
    Tempo de resposta (p95) do ALB público que dispara o alarme. As respostas
    do chat incluem a chamada ao modelo (~4 s), por isso o limite é folgado.
  EOT
  type        = number
  default     = 10
}
