variable "name" {
  description = "Nome do serviço (ex.: backend-api)."
  type        = string
}

variable "name_prefix" {
  description = "Prefixo dos nomes (ex.: convcommerce-sp)."
  type        = string
}

variable "region" {
  description = "Região (para o envio de logs)."
  type        = string
}

variable "cluster_name" {
  description = "Cluster ECS onde o serviço roda."
  type        = string
}

variable "capacity_provider_name" {
  description = "Capacity Provider que fornece as instâncias."
  type        = string
}

variable "image" {
  description = "Imagem do container, com a tag."
  type        = string
}

# --- Recursos do container ----------------------------------------------
# cpu: unidades de CPU reservadas (1024 = 1 vCPU) - usadas para posicionar a task.
# memory: limite rígido em MiB - acima disso o container é encerrado.
# memory_reservation: reserva em MiB - o que o ECS desconta da instância.

variable "cpu" {
  description = "Unidades de CPU reservadas (1024 = 1 vCPU)."
  type        = number
}

variable "memory" {
  description = "Limite de memória em MiB."
  type        = number
}

variable "memory_reservation" {
  description = "Memória reservada em MiB (menor ou igual ao limite)."
  type        = number
}

variable "container_port" {
  description = "Porta em que a aplicação escuta. null para serviços sem HTTP."
  type        = number
  default     = null
}

variable "environment" {
  description = "Variáveis de ambiente (valores não secretos)."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Variáveis vindas do Secrets Manager ou SSM: nome -> ARN."
  type        = map(string)
  default     = {}
}

variable "health_check_command" {
  description = "Comando do health check do container."
  type        = list(string)
}

variable "health_check_interval" {
  description = "Intervalo do health check do container, em segundos."
  type        = number
  default     = 15
}

variable "health_check_start_period" {
  description = "Tempo de tolerância na partida do container, em segundos."
  type        = number
  default     = 30
}

variable "execution_role_arn" {
  description = "Role de execução (imagens, logs, segredos)."
  type        = string
}

variable "task_role_arn" {
  description = "Role da aplicação."
  type        = string
}

variable "log_group_prefix" {
  description = "Prefixo do log group (ex.: /convcommerce/sp)."
  type        = string
}

variable "log_retention_days" {
  description = "Dias de retenção dos logs."
  type        = number
  default     = 14
}

variable "load_balancers" {
  description = "Target groups em que as tasks se registram."
  type        = list(string)
  default     = []
}

# --- Escala --------------------------------------------------------------

variable "min_tasks" {
  description = "Mínimo de tasks (também é o número inicial)."
  type        = number
}

variable "max_tasks" {
  description = "Máximo de tasks."
  type        = number
}

variable "cpu_target" {
  description = "Escala para manter a CPU média neste %. null desliga."
  type        = number
  default     = null
}

variable "requests_per_target" {
  description = <<-EOT
    Escala para manter este número de requisições por task, por minuto.
    resource_label: app/<alb>/targetgroup/<tg>. null desliga.
  EOT
  type = object({
    target         = number
    resource_label = string
  })
  default = null
}

variable "sqs_backlog" {
  description = "Escala para manter este número de mensagens na fila por task. null desliga."
  type = object({
    target     = number
    queue_name = string
  })
  default = null
}

variable "scale_in_cooldown" {
  description = "Espera depois de remover tasks, em segundos."
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Espera depois de adicionar tasks, em segundos."
  type        = number
  default     = 60
}
