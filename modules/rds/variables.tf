variable "name_prefix" {
  description = "Prefixo dos nomes dos recursos (ex.: convcommerce-sp)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas onde o banco pode ficar."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group do RDS (só aceita as instâncias ECS)."
  type        = string
}

variable "db_name" {
  description = "Nome do banco criado na instância."
  type        = string
  default     = "convcommerce"
}

variable "master_username" {
  description = "Usuário administrador. A senha é gerada e guardada pelo próprio RDS."
  type        = string
  default     = "convcommerce"
}

variable "engine_version" {
  description = "Versão do Postgres. Só a principal: o RDS aplica as correções menores."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "Tamanho da instância."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Disco inicial, em GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Limite do crescimento automático do disco, em GB."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "true: réplica em espera em outra zona (dobra o custo)."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Dias de backup automático."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Impede apagar o banco. Fica false para o destroy do ambiente funcionar."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "false: tira um snapshot final antes de apagar o banco."
  type        = bool
  default     = true
}
