#!/usr/bin/env bash
# Comprova que o ambiente criado pelo Terraform não depende de Ohio (nem de
# nenhuma outra região) e que o destroy não deixa nada para trás.
#
# Uso (a partir da raiz do repositório):
#   scripts/check-portability.sh              código + ambiente no ar
#   scripts/check-portability.sh --destroyed  código + nada sobrou após o destroy
#
# Variáveis de ambiente:
#   AWS_PROFILE  perfil da AWS CLI (ex.: cirro-admin)
#   APPS_DIR     pasta com os repositórios da aplicação (padrão: pasta acima
#                deste repositório)
#
# Sai com código 0 só se todas as verificações passarem.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFRA="$ROOT/infra"
APPS_DIR="${APPS_DIR:-$(dirname "$ROOT")}"
MODE="${1:-live}"

FAILS=0
pass() { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFALHA\033[0m %s\n' "$1"; FAILS=$((FAILS + 1)); }
note() { printf '  \033[33mNOTA\033[0m  %s\n' "$1"; }
title() { printf '\n\033[1m%s\033[0m\n' "$1"; }
indent() { sed 's/^/          /'; }

ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" || {
  echo "sem credenciais da AWS (aws sso login --profile ...)" >&2
  exit 2
}

# Região, prefixo e conta vêm da configuração do Terraform, não deste script.
tf_eval() { echo "$1" | terraform -chdir="$INFRA" console 2>/dev/null | tr -d '"'; }
REGION="$(tf_eval var.region)"
PREFIX="$(tf_eval local.name_prefix)"
PROJECT="$(tf_eval var.project)"
ENVIRONMENT="$(tf_eval var.environment)"
if [[ -z "$REGION" || -z "$PREFIX" ]]; then
  echo "não consegui ler a configuração do Terraform (rode terraform init em infra/)" >&2
  exit 2
fi
AWS=(aws --region "$REGION" --output text)

echo "Região: $REGION | prefixo: $PREFIX | conta: $ACCOUNT | modo: $MODE"

# Padrões de coisas que amarram o código a uma região ou a recursos existentes.
RE_REGION='\b(us|eu|ap|sa|ca|me|af|il|mx)-(east|west|north|south|central|northeast|southeast|northwest|southwest)-[0-9]\b'
RE_IDS='\b(ami|vpc|subnet|sg|igw|nat|rtb|eni|eipalloc|lt|i)-[0-9a-f]{8,17}\b'
RE_ECR='[0-9]{12}\.dkr\.ecr\.'

# Linhas de código, sem comentários de linha inteira (# ou //).
code_lines() {
  grep -rnE "$1" "${@:2}" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:\s*(#|//)'
}

# ---------------------------------------------------------------------------
title "1. Código Terraform e scripts"

TF_FILES=(--include='*.tf' --include='*.sh' --include='*.hcl' --exclude-dir=.terraform)

# A região só pode aparecer como valor padrão da variável "region" e no
# backend.hcl (a região do bucket de estado, gerado pelo bootstrap).
hits="$(code_lines "$RE_REGION" "${TF_FILES[@]}" "$ROOT/infra" "$ROOT/modules" "$ROOT/scripts" "$ROOT/bootstrap" \
  | grep -vE '/(infra|bootstrap)/variables\.tf:[0-9]+:\s*default\s*=' \
  | grep -vE '/infra/backend\.hcl:[0-9]+:\s*region\s*=')"
if [[ -z "$hits" ]]; then
  pass "nenhuma região fixa no código (só o valor padrão da variável region)"
else
  fail "região fixa no código:"; echo "$hits" | indent
fi

hits="$(code_lines "$RE_IDS" "${TF_FILES[@]}" "$ROOT/infra" "$ROOT/modules" "$ROOT/scripts")"
if [[ -z "$hits" ]]; then
  pass "nenhum ID fixo de AMI, VPC, subnet, security group ou instância"
else
  fail "IDs fixos no código:"; echo "$hits" | indent
fi

hits="$(code_lines "$RE_ECR|arn:aws:[a-z0-9-]+:[a-z]{2}-[a-z]+-[0-9]:" "${TF_FILES[@]}" "$ROOT/infra" "$ROOT/modules" "$ROOT/scripts")"
if [[ -z "$hits" ]]; then
  pass "nenhum ARN ou endereço de ECR escrito à mão"
else
  fail "ARNs ou registros de ECR fixos:"; echo "$hits" | indent
fi

grep -q 'aws/service/ecs/optimized-ami' "$ROOT/modules/ecs-cluster/main.tf" \
  && pass "AMI lida do parâmetro público do SSM da região" \
  || fail "AMI não vem do parâmetro público do SSM"
grep -q 'aws_availability_zones' "$INFRA/locals.tf" \
  && pass "zonas lidas da região (aws_availability_zones)" \
  || fail "zonas não vêm da região"

# ---------------------------------------------------------------------------
title "2. Código da aplicação ($APPS_DIR)"

APP_FILES=(--include='*.py' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.conf'
  --include='Dockerfile*' --include='*.toml' --include='*.yml' --include='*.yaml'
  --exclude-dir=tests --exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=dist --exclude-dir=.git)
found_app=0
for repo in "$APPS_DIR"/projeto-cloud-{backend,chatbot,frontend}; do
  [[ -d "$repo" ]] || continue
  found_app=1
  name="$(basename "$repo")"
  # docker-compose e scripts de ambiente local não vão para a imagem.
  hits="$(code_lines "$RE_REGION|$RE_IDS|$RE_ECR" "${APP_FILES[@]}" "$repo" | grep -vE 'docker-compose|compose\.ya?ml')"
  if [[ -z "$hits" ]]; then
    pass "$name: nenhuma região, ID ou registro fixo"
  else
    fail "$name: valores de região fixos (a aplicação usaria esta região se a variável faltar):"
    echo "$hits" | sed "s#^$repo/##" | indent
  fi
done
[[ $found_app == 1 ]] || note "repositórios da aplicação não encontrados em $APPS_DIR (pulado)"

# ---------------------------------------------------------------------------
if [[ "$MODE" == "--destroyed" ]]; then
  title "3. Sobras depois do destroy"

  n="$(terraform -chdir="$INFRA" state list 2>/dev/null | wc -l)"
  [[ "$n" == 0 ]] && pass "state vazio" || fail "state ainda tem $n recursos"

  check_empty() { # descrição, saída do comando
    local out
    out="$(echo "$2" | grep -vE '^\s*$|^None$')"
    if [[ -z "$out" ]]; then pass "$1: nenhum"; else fail "$1:"; echo "$out" | indent; fi
  }
  TAGS=(Name=tag:Project,Values="$PROJECT" Name=tag:Environment,Values="$ENVIRONMENT")

  check_empty "instâncias EC2" "$("${AWS[@]}" ec2 describe-instances --filters "${TAGS[@]}" \
    Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId')"
  check_empty "VPCs" "$("${AWS[@]}" ec2 describe-vpcs --filters "${TAGS[@]}" --query 'Vpcs[].VpcId')"
  check_empty "NAT gateways" "$("${AWS[@]}" ec2 describe-nat-gateways --filter "${TAGS[@]}" \
    Name=state,Values=pending,available,deleting --query 'NatGateways[].NatGatewayId')"
  check_empty "IPs elásticos" "$("${AWS[@]}" ec2 describe-addresses --filters "${TAGS[@]}" --query 'Addresses[].PublicIp')"
  check_empty "volumes EBS" "$("${AWS[@]}" ec2 describe-volumes --filters "${TAGS[@]}" --query 'Volumes[].VolumeId')"
  check_empty "security groups" "$("${AWS[@]}" ec2 describe-security-groups --filters "${TAGS[@]}" --query 'SecurityGroups[].GroupId')"
  check_empty "launch templates" "$("${AWS[@]}" ec2 describe-launch-templates --query "LaunchTemplates[?starts_with(LaunchTemplateName, '$PREFIX')].LaunchTemplateName")"
  check_empty "auto scaling groups" "$("${AWS[@]}" autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?starts_with(AutoScalingGroupName, '$PREFIX')].AutoScalingGroupName")"
  check_empty "load balancers" "$("${AWS[@]}" elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName, '$PREFIX')].LoadBalancerName")"
  check_empty "target groups" "$("${AWS[@]}" elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName, '$PREFIX')].TargetGroupName")"
  check_empty "clusters ECS" "$("${AWS[@]}" ecs describe-clusters --clusters "$PREFIX" --query "clusters[?status=='ACTIVE'].clusterName")"
  check_empty "repositórios ECR" "$("${AWS[@]}" ecr describe-repositories --query "repositories[?starts_with(repositoryName, '$PROJECT/')].repositoryName")"
  check_empty "bancos RDS" "$("${AWS[@]}" rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier, '$PREFIX')].DBInstanceIdentifier")"
  check_empty "tabelas DynamoDB" "$("${AWS[@]}" dynamodb list-tables --query "TableNames[?starts_with(@, '$PREFIX')]")"
  check_empty "filas SQS" "$("${AWS[@]}" sqs list-queues --queue-name-prefix "$PREFIX" --query 'QueueUrls')"
  check_empty "tópicos SNS" "$("${AWS[@]}" sns list-topics --query "Topics[?contains(TopicArn, ':$PREFIX-')].TopicArn")"
  check_empty "parâmetros SSM" "$("${AWS[@]}" ssm get-parameters-by-path --path "/$PROJECT/$ENVIRONMENT" --recursive --query 'Parameters[].Name')"
  check_empty "alarmes" "$("${AWS[@]}" cloudwatch describe-alarms --alarm-name-prefix "$PREFIX" --query 'MetricAlarms[].AlarmName')"
  check_empty "dashboards" "$("${AWS[@]}" cloudwatch list-dashboards --dashboard-name-prefix "$PREFIX" --query 'DashboardEntries[].DashboardName')"
  check_empty "log groups da aplicação" "$("${AWS[@]}" logs describe-log-groups --log-group-name-prefix "/$PROJECT/$ENVIRONMENT" --query 'logGroups[].logGroupName')"
  check_empty "roles IAM" "$(aws iam list-roles --output text --query "Roles[?starts_with(RoleName, '$PREFIX-')].RoleName")"
  check_empty "orçamentos" "$(aws budgets describe-budgets --account-id "$ACCOUNT" --output text --query "Budgets[?starts_with(BudgetName, '$PREFIX-')].BudgetName")"
  check_empty "instance profiles" "$(aws iam list-instance-profiles --output text --query "InstanceProfiles[?starts_with(InstanceProfileName, '$PREFIX-')].InstanceProfileName")"

  # Criado pelo próprio ECS quando o Container Insights liga; o Terraform não
  # o cria. Não impede uma recriação (o ECS reaproveita) e expira em 1 dia.
  ci="$("${AWS[@]}" logs describe-log-groups --log-group-name-prefix "/aws/ecs/containerinsights/$PREFIX" --query 'logGroups[].logGroupName')"
  [[ -n "$ci" && "$ci" != None ]] && note "log group criado pela AWS (não pelo Terraform), sem efeito numa recriação: $ci"

else
  title "3. Ambiente no ar"

  STATE="$(terraform -chdir="$INFRA" state pull 2>/dev/null)"
  if [[ -z "$STATE" ]] || [[ "$(echo "$STATE" | jq '.resources | length')" == 0 ]]; then
    fail "state vazio: suba o ambiente ou use --destroyed"
  else
    total="$(echo "$STATE" | grep -oE 'arn:aws:[a-z0-9-]+:[a-z0-9-]*:' | wc -l)"
    other="$(echo "$STATE" | grep -oE 'arn:aws:[a-z0-9-]+:[a-z]{2}-[a-z]+-[0-9]:|com\.amazonaws\.[a-z]{2}-[a-z]+-[0-9]|"[a-z]{2}-[a-z]+-[0-9][a-z]"' \
      | grep -v "$REGION" | sort | uniq -c)"
    if [[ -z "$other" ]]; then
      pass "state: $total ARNs, todos em $REGION ou globais; zonas e endpoints só de $REGION"
    else
      fail "state referencia outra região:"; echo "$other" | indent
    fi

    CLUSTER="$PREFIX"
    images="$(for svc in $("${AWS[@]}" ecs list-services --cluster "$CLUSTER" --query 'serviceArns[]'); do
      td="$("${AWS[@]}" ecs describe-services --cluster "$CLUSTER" --services "$svc" --query 'services[0].taskDefinition')"
      "${AWS[@]}" ecs describe-task-definition --task-definition "$td" --query 'taskDefinition.containerDefinitions[].image' | tr '\t' '\n'
    done)"
    bad="$(echo "$images" | grep -v "^$ACCOUNT\.dkr\.ecr\.$REGION\.amazonaws\.com/")"
    if [[ -n "$images" && -z "$bad" ]]; then
      pass "imagens dos serviços: todas do ECR de $REGION ($(echo "$images" | wc -l) containers)"
      echo "$images" | indent
    else
      fail "imagens fora do ECR de $REGION:"; echo "${bad:-nenhum serviço encontrado}" | indent
    fi

    regions="$(for svc in $("${AWS[@]}" ecs list-services --cluster "$CLUSTER" --query 'serviceArns[]'); do
      td="$("${AWS[@]}" ecs describe-services --cluster "$CLUSTER" --services "$svc" --query 'services[0].taskDefinition')"
      "${AWS[@]}" ecs describe-task-definition --task-definition "$td" \
        --query "taskDefinition.containerDefinitions[].environment[?name=='AWS_REGION'].value[]"
    done | tr '\t' '\n' | sort | uniq -c)"
    if [[ "$(echo "$regions" | awk '{print $2}' | sort -u)" == "$REGION" ]]; then
      pass "AWS_REGION=$REGION em todos os serviços"
    else
      fail "AWS_REGION ausente ou diferente nos serviços:"; echo "${regions:-nenhum}" | indent
    fi

    expected_ami="$("${AWS[@]}" ssm get-parameter --name /aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id --query Parameter.Value)"
    running_ami="$("${AWS[@]}" ec2 describe-instances --filters "Name=tag:aws:autoscaling:groupName,Values=$PREFIX-ecs" \
      Name=instance-state-name,Values=running --query 'Reservations[].Instances[].ImageId' | tr '\t' '\n' | sort -u)"
    # A AMI tem que ser uma AMI ECS da Amazon que existe nesta região. Uma AMI
    # copiada de outra região não teria dono "amazon" nem existiria aqui.
    for ami in $running_ami; do
      ami_name="$("${AWS[@]}" ec2 describe-images --owners amazon --image-ids "$ami" --query 'Images[0].Name' 2>/dev/null)"
      if [[ "$ami_name" == *ecs* ]]; then
        pass "instâncias rodando AMI ECS da Amazon publicada em $REGION ($ami, $ami_name)"
      else
        fail "AMI $ami não é uma AMI ECS da Amazon em $REGION"
      fi
    done
    [[ -n "$running_ami" ]] || fail "nenhuma instância do ASG rodando"
    if [[ -n "$running_ami" && "$running_ami" != "$expected_ami" ]]; then
      note "a AWS já publicou uma AMI ECS mais nova ($expected_ami); o próximo apply cria uma versão nova do launch template, e as instâncias que o ASG criar depois disso já usam a AMI nova"
    fi

    azs="$("${AWS[@]}" ec2 describe-instances --filters "Name=tag:aws:autoscaling:groupName,Values=$PREFIX-ecs" \
      Name=instance-state-name,Values=running --query 'Reservations[].Instances[].Placement.AvailabilityZone' | tr '\t' '\n' | sort -u | paste -sd' ')"
    pass "instâncias nas zonas: $azs"
  fi
fi

# ---------------------------------------------------------------------------
echo
if [[ $FAILS == 0 ]]; then
  printf '\033[32mTudo certo: nenhuma dependência de outra região.\033[0m\n'
else
  printf '\033[31m%d verificação(ões) falharam.\033[0m\n' "$FAILS"
fi
exit $(( FAILS > 0 ))
