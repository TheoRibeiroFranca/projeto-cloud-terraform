output "state_bucket" {
  description = "Nome do bucket do state, para usar em infra/backend.hcl."
  value       = aws_s3_bucket.state.id
}

output "backend_hcl" {
  description = "Conteúdo pronto para o arquivo infra/backend.hcl."
  value       = <<-EOT
    bucket = "${aws_s3_bucket.state.id}"
    region = "${var.region}"
  EOT
}
