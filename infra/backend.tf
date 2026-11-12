# O bucket e a região vêm de backend.hcl (gerado pelo bootstrap):
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "infra/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # trava nativa do S3: impede dois applies ao mesmo tempo
  }
}
