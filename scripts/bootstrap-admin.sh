#!/usr/bin/env bash
# Cria a conta de administrador da loja, sem passo manual:
#   1. lê a senha que o Terraform gerou e guardou no SSM
#   2. cadastra a conta pela API pública, como um cliente faria
#      (se já existir, a API responde 409 e o script segue)
#   3. promove a conta a admin com `app.cli set-role`, numa task avulsa
#
# A senha não passa pelo Terraform nem fica no state: só existe no SSM.
#
# Variáveis de ambiente (o Terraform passa): STORE_URL, ADMIN_EMAIL,
# ADMIN_NAME, ADMIN_PASSWORD_PARAMETER, BACKEND_SERVICE, FAMILY, CLUSTER,
# CAPACITY_PROVIDER, REGION.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> esperando o backend ficar estável"
aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" --services "$BACKEND_SERVICE"

PASSWORD="$(aws ssm get-parameter --region "$REGION" --name "$ADMIN_PASSWORD_PARAMETER" \
  --with-decryption --query Parameter.Value --output text)"

BODY="$(ADMIN_EMAIL="$ADMIN_EMAIL" ADMIN_NAME="$ADMIN_NAME" PASSWORD="$PASSWORD" python3 -c \
  'import json,os; print(json.dumps({"email":os.environ["ADMIN_EMAIL"],"name":os.environ["ADMIN_NAME"],"password":os.environ["PASSWORD"]}))')"

echo "==> cadastrando $ADMIN_EMAIL"
STATUS="$(curl -sS -o /dev/null -w '%{http_code}' --retry 5 --retry-delay 5 --retry-all-errors \
  -X POST "$STORE_URL/api/auth/register" -H 'content-type: application/json' --data "$BODY")"

case "$STATUS" in
  201) echo "    conta criada" ;;
  409) echo "    conta já existia" ;;
  *)   echo "    cadastro falhou: HTTP $STATUS" >&2; exit 1 ;;
esac

"$HERE/run-task.sh" "$FAMILY" python -m app.cli set-role --email "$ADMIN_EMAIL" --role admin
