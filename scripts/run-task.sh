#!/usr/bin/env bash
# Roda um comando numa task avulsa do ECS, usando a task definition de um
# serviço (mesma imagem, roles, segredos e variáveis), espera terminar e
# falha se o comando falhar.
#
# Uso: run-task.sh <família da task definition> <comando> [argumentos...]
#   ex.: run-task.sh convcommerce-sp-backend-api python -m app.cli embed
#
# Variáveis de ambiente: CLUSTER, CAPACITY_PROVIDER, REGION (o Terraform passa).
set -euo pipefail

FAMILY="$1"
shift

# Comando em JSON (["python","-m",...]) para o override do container "app".
COMMAND_JSON="$(printf '%s\n' "$@" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))')"
OVERRIDES="$(printf '{"containerOverrides":[{"name":"app","command":%s}]}' "$COMMAND_JSON")"

echo "==> task avulsa ($FAMILY): $*"
TASK_ARN="$(aws ecs run-task \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --task-definition "$FAMILY" \
  --capacity-provider-strategy "capacityProvider=$CAPACITY_PROVIDER,weight=1" \
  --overrides "$OVERRIDES" \
  --started-by terraform \
  --query 'tasks[0].taskArn' --output text)"

if [[ -z "$TASK_ARN" || "$TASK_ARN" == "None" ]]; then
  echo "não foi possível iniciar a task" >&2
  exit 1
fi

# O waiter desiste depois de 10 minutos; uma task avulsa dura segundos.
aws ecs wait tasks-stopped --region "$REGION" --cluster "$CLUSTER" --tasks "$TASK_ARN"

read -r EXIT_CODE REASON < <(aws ecs describe-tasks \
  --region "$REGION" --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].[containers[0].exitCode, stoppedReason]' --output text)

TASK_ID="${TASK_ARN##*/}"
echo "    task $TASK_ID terminou com código $EXIT_CODE ($REASON)"
echo "    logs: no log group do serviço, stream ecs/app/$TASK_ID"

[[ "$EXIT_CODE" == "0" ]]
