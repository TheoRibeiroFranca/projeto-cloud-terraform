# Constrói e envia as imagens para o ECR desta região durante o apply, entre a
# criação do ECR e a dos serviços. Assim o ambiente sobe com um único
# terraform apply, sem passo manual e sem usar o ECR de Ohio.
#
# Requer Docker e os repositórios de código ao lado deste (var.app_source_dir).
# Para publicar uma versão nova, mude var.image_tag: as imagens são
# reconstruídas e os serviços fazem um deploy sem queda.

resource "terraform_data" "images" {
  count = var.build_images ? 1 : 0

  triggers_replace = {
    tag      = var.image_tag
    registry = module.ecr.registry
  }

  provisioner "local-exec" {
    command = "${path.root}/../scripts/push-images.sh ${var.image_tag}"

    environment = {
      REGISTRY          = module.ecr.registry
      REGION            = var.region
      REPOSITORY_PREFIX = local.names.ecr_repository_prefix
      SRC_DIR           = abspath(var.app_source_dir)
    }
  }
}

locals {
  image_urls = { for svc, url in module.ecr.repository_urls : svc => "${url}:${var.image_tag}" }
}
