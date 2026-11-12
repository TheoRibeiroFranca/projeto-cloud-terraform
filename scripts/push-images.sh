#!/usr/bin/env bash
# Constrói as imagens a partir do código-fonte e envia para o ECR de São Paulo.
# Não usa o ECR de Ohio: as imagens nascem do código, nesta região.
#
# Uso (da raiz deste repositório, depois do terraform apply que cria o ECR):
#   AWS_PROFILE=cirro-admin ./scripts/push-images.sh [tag]
#
# Os repositórios de código ficam ao lado deste, por padrão em ..:
#   ../projeto-cloud-backend   -> backend-api e order-worker
#   ../projeto-cloud-chatbot   -> chatbot
#   ../projeto-cloud-frontend  -> frontend
set -euo pipefail

TAG="${1:-$(date +%Y%m%d-%H%M%S)}"
SRC="${SRC_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
INFRA="$(cd "$(dirname "$0")/../infra" && pwd)"

REGISTRY="$(terraform -chdir="$INFRA" output -raw ecr_registry)"
REGION="$(terraform -chdir="$INFRA" output -raw region)"

# serviço | diretório do código | target do Dockerfile (vazio = o último estágio)
# O backend tem um Dockerfile só, com um estágio para a API e outro para o worker.
SERVICES=(
  "backend-api|projeto-cloud-backend|api"
  "order-worker|projeto-cloud-backend|worker"
  "chatbot|projeto-cloud-chatbot|"
  "frontend|projeto-cloud-frontend|"
)

aws ecr get-login-password --region "$REGION" |
  docker login --username AWS --password-stdin "$REGISTRY"

for entry in "${SERVICES[@]}"; do
  IFS='|' read -r service dir target <<<"$entry"
  image="$REGISTRY/convcommerce/$service"
  target_arg=()
  [[ -n "$target" ]] && target_arg=(--target "$target")

  echo "==> $service ($dir${target:+, target $target}) -> $image:$TAG"
  docker build --platform linux/amd64 "${target_arg[@]}" \
    -t "$image:$TAG" -t "$image:latest" "$SRC/$dir"
  docker push "$image:$TAG"
  docker push "$image:latest"
done

echo "Imagens enviadas com a tag $TAG."
