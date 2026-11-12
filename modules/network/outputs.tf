output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Faixa de IPs da VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Subnets públicas (ALB público, NAT)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Subnets privadas (instâncias ECS, ALB interno, RDS)."
  value       = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  description = "Tabelas de rotas privadas."
  value       = aws_route_table.private[*].id
}

output "nat_public_ips" {
  description = "IPs públicos de saída das subnets privadas."
  value       = aws_eip.nat[*].public_ip
}
