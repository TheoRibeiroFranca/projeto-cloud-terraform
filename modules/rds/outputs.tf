output "address" {
  description = "Endereço do banco (DB_HOST das aplicações)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Porta do banco."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Nome do banco."
  value       = aws_db_instance.this.db_name
}

output "master_secret_arn" {
  description = "Segredo do Secrets Manager com usuário e senha, criado pelo RDS."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "identifier" {
  description = "Identificador da instância (métricas do CloudWatch)."
  value       = aws_db_instance.this.identifier
}
