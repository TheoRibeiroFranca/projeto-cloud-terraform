variable "name_prefix" {
  description = "Prefixo dos nomes dos recursos (ex.: convcommerce-sp)."
  type        = string
}

variable "vpc_id" {
  description = "VPC onde os security groups são criados."
  type        = string
}

variable "names" {
  description = <<-EOT
    Nomes dos recursos que as roles acessam. Os recursos são criados por outros
    módulos com estes mesmos nomes; aqui eles viram ARNs exatos, sem curingas largos.
  EOT
  type = object({
    ecr_repository_prefix = string # ex.: convcommerce (repositórios convcommerce/*)
    log_group_prefix      = string # ex.: /convcommerce/sp
    ssm_prefix            = string # ex.: /convcommerce/sp
    orders_queue          = string
    conversations_table   = string
  })
}

variable "rds_secret_arn" {
  description = "Segredo com usuário e senha do banco, criado pelo próprio RDS."
  type        = string
}

variable "bedrock_chat_inference_profile" {
  description = "Perfil de inferência do modelo do chat."
  type        = string
  default     = "global.anthropic.claude-haiku-5-5"
}

variable "bedrock_chat_model_id" {
  description = "Modelo base por trás do perfil de inferência do chat."
  type        = string
  default     = "anthropic.claude-haiku-5-5"
}

variable "bedrock_embedding_model_id" {
  description = "Modelo de embeddings da busca semântica."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}
