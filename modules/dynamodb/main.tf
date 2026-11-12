variable "table_name" {
  description = "Nome da tabela de conversas."
  type        = string
}

variable "point_in_time_recovery" {
  description = "Backup contínuo: permite voltar a tabela a qualquer momento dos últimos 35 dias."
  type        = bool
  default     = true
}

# Conversas do chat. Mesma chave de Ohio: conversation_id + sk.
#
# O TTL continua ligado em expires_at: as conversas não expiram mais, mas o
# chatbot grava com prazo os registros que evitam processar a mesma requisição
# duas vezes (app/adapters/conversations.py).
resource "aws_dynamodb_table" "conversations" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "conversation_id"
  range_key    = "sk"

  attribute {
    name = "conversation_id"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = var.table_name }
}

output "table_name" {
  description = "Nome da tabela."
  value       = aws_dynamodb_table.conversations.name
}

output "table_arn" {
  description = "ARN da tabela."
  value       = aws_dynamodb_table.conversations.arn
}
