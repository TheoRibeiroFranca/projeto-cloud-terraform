variable "repository_prefix" {
  description = "Prefixo dos repositórios (ex.: convcommerce, para convcommerce/backend-api)."
  type        = string
}

variable "services" {
  description = "Serviços que ganham um repositório de imagens."
  type        = list(string)
}

variable "keep_images" {
  description = "Quantas imagens com tag manter por repositório; as mais antigas são apagadas."
  type        = number
  default     = 10
}

# Um repositório por serviço, no ECR desta região. Nada depende do ECR de Ohio.
resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name                 = "${var.repository_prefix}/${each.key}"
  image_tag_mutability = "MUTABLE"

  # Permite o terraform destroy mesmo com imagens dentro.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Evita acumular imagens velhas (e custo de armazenamento).
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Apaga imagens sem tag depois de 1 dia"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Mantém só as ${var.keep_images} imagens mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

output "repository_urls" {
  description = "URL de cada repositório, por serviço."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "registry" {
  description = "Endereço do registro (para o docker login)."
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}
