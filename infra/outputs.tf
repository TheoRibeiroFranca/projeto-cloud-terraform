output "region" {
  description = "Região do ambiente."
  value       = var.region
}

output "availability_zones" {
  description = "Zonas usadas pelo ambiente."
  value       = local.azs
}
