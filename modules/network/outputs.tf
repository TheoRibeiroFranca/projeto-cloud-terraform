output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Faixa de IPs da VPC."
  value       = aws_vpc.this.cidr_block
}

# As subnets só saem do módulo com a saída para a internet pronta. Quem as usa
# (instâncias, ALBs, RDS) é criado depois das rotas, do NAT e do gateway, e
# apagado antes deles. Sem isso, o destroy apagava o NAT primeiro: as
# instâncias perdiam contato com o ECS e os serviços travavam em DRAINING.
output "public_subnet_ids" {
  description = "Subnets públicas (ALB público, NAT)."
  value       = aws_subnet.public[*].id

  depends_on = [
    aws_route.public_internet,
    aws_route_table_association.public,
  ]
}

output "private_subnet_ids" {
  description = "Subnets privadas (instâncias ECS, ALB interno, RDS)."
  value       = aws_subnet.private[*].id

  depends_on = [
    aws_route.private_nat,
    aws_route_table_association.private,
    aws_vpc_endpoint.gateway,
  ]
}

output "private_route_table_ids" {
  description = "Tabelas de rotas privadas."
  value       = aws_route_table.private[*].id
}

output "nat_public_ips" {
  description = "IPs públicos de saída das subnets privadas."
  value       = aws_eip.nat[*].public_ip
}
