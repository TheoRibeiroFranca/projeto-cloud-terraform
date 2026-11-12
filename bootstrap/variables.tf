variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
  default     = "convcommerce"
}

variable "region" {
  description = "Região onde o bucket do state é criado."
  type        = string
  default     = "sa-east-1"
}
