output "region" {
  description = "Região do ambiente."
  value       = var.region
}

output "availability_zones" {
  description = "Zonas usadas pelo ambiente."
  value       = local.azs
}

output "vpc_id" {
  description = "ID da VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Subnets públicas."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Subnets privadas."
  value       = module.network.private_subnet_ids
}

output "nat_public_ips" {
  description = "IPs públicos de saída das subnets privadas."
  value       = module.network.nat_public_ips
}

output "rds_address" {
  description = "Endereço do Postgres."
  value       = module.rds.address
}

output "rds_secret_arn" {
  description = "Segredo com usuário e senha do banco."
  value       = module.rds.master_secret_arn
}

output "conversations_table" {
  description = "Tabela de conversas."
  value       = module.dynamodb.table_name
}

output "orders_queue_url" {
  description = "Fila de pedidos."
  value       = module.sqs.queue_url
}
