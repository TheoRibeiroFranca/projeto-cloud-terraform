variable "queue_name" {
  description = "Nome da fila de pedidos."
  type        = string
}

variable "dlq_name" {
  description = "Nome da dead-letter queue."
  type        = string
}

variable "max_receive_count" {
  description = "Tentativas antes de a mensagem ir para a DLQ."
  type        = number
  default     = 3
}

variable "visibility_timeout_seconds" {
  description = "Tempo que o worker tem para processar uma mensagem antes de ela voltar à fila."
  type        = number
  default     = 60
}

# Fila de pedidos: o backend publica, o order-worker consome.
#
# Uma mensagem que falha volta para a fila depois do visibility timeout.
# Depois de max_receive_count tentativas, vai para a DLQ, onde fica 14 dias
# para análise em vez de travar a fila.

resource "aws_sqs_queue" "dlq" {
  name                      = var.dlq_name
  message_retention_seconds = 1209600 # 14 dias, o máximo
  sqs_managed_sse_enabled   = true

  tags = { Name = var.dlq_name }
}

resource "aws_sqs_queue" "orders" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = 345600 # 4 dias
  receive_wait_time_seconds  = 20     # long polling: menos chamadas vazias
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = { Name = var.queue_name }
}

# Só a fila de pedidos pode mandar mensagens para esta DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.orders.arn]
  })
}

output "queue_url" {
  description = "URL da fila de pedidos (usada pelas aplicações)."
  value       = aws_sqs_queue.orders.id
}

output "queue_name" {
  description = "Nome da fila de pedidos."
  value       = aws_sqs_queue.orders.name
}

output "queue_arn" {
  description = "ARN da fila de pedidos."
  value       = aws_sqs_queue.orders.arn
}

output "dlq_name" {
  description = "Nome da DLQ (para o alarme de mensagens com falha)."
  value       = aws_sqs_queue.dlq.name
}
