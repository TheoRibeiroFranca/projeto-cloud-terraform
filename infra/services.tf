# Load balancers e os 4 serviços da aplicação.
#
# Valores de CPU e memória: os mesmos de Ohio. Uma t3.small tem 2048 unidades
# de CPU e ~1,9 GB disponíveis para tasks; o ECS posiciona as tasks pela reserva
# (cpu e memory_reservation), e o limite (memory) é o teto de cada container.
#
#   serviço        cpu   reserva  limite   tasks
#   frontend        64     64 MB  128 MB   2-4
#   backend-api    256    256 MB  512 MB   2-8
#   chatbot        256    256 MB  512 MB   2-8
#   order-worker   128    128 MB  256 MB   1-6

module "alb" {
  source = "../modules/alb"

  name_prefix                = local.name_prefix
  vpc_id                     = module.network.vpc_id
  public_subnet_ids          = module.network.public_subnet_ids
  private_subnet_ids         = module.network.private_subnet_ids
  public_security_group_id   = module.security.security_group_ids.alb
  internal_security_group_id = module.security.security_group_ids.alb_internal
}

locals {
  # Comum a todos os serviços que chamam a AWS.
  common_env = {
    AWS_REGION       = var.region
    APP_ENV          = "prod"
    FAULTS_PARAMETER = module.parameters.faults_parameter_name
  }

  # Banco: endereço em texto, usuário e senha vindos do segredo do RDS.
  db_env = {
    DB_HOST    = module.rds.address
    DB_PORT    = tostring(module.rds.port)
    DB_NAME    = module.rds.db_name
    DB_SSLMODE = "require"
    # O RDS troca a senha a cada 7 dias. Com o ARN, a aplicação relê o segredo
    # quando o Postgres recusa a senha antiga (db_credentials.py no backend).
    DB_SECRET_ARN = module.rds.master_secret_arn
  }

  db_secrets = {
    DB_USER     = "${module.rds.master_secret_arn}:username::"
    DB_PASSWORD = "${module.rds.master_secret_arn}:password::"
  }

  service_defaults = {
    name_prefix            = local.name_prefix
    region                 = var.region
    cluster_name           = module.ecs_cluster.cluster_name
    capacity_provider_name = module.ecs_cluster.capacity_provider_name
    execution_role_arn     = module.security.task_execution_role_arn
    log_group_prefix       = local.names.log_group_prefix
  }
}

# --- frontend: páginas da loja -------------------------------------------

module "frontend" {
  source     = "../modules/ecs-service"
  depends_on = [terraform_data.images]

  name                   = "frontend"
  name_prefix            = local.service_defaults.name_prefix
  region                 = local.service_defaults.region
  cluster_name           = local.service_defaults.cluster_name
  capacity_provider_name = local.service_defaults.capacity_provider_name
  execution_role_arn     = local.service_defaults.execution_role_arn
  log_group_prefix       = local.service_defaults.log_group_prefix
  task_role_arn          = module.security.app_role_arns["frontend"]
  image                  = local.image_urls["frontend"]

  cpu                = 64
  memory             = 128
  memory_reservation = 64
  container_port     = 8080

  health_check_command      = ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1"]
  health_check_start_period = 10

  load_balancers = [module.alb.target_group_arns["frontend"]]

  # Em Ohio o frontend não escala; aqui escala por CPU.
  min_tasks  = 2
  max_tasks  = 4
  cpu_target = 60
}

# --- backend-api: catálogo, contas, pedidos -------------------------------

module "backend_api" {
  source     = "../modules/ecs-service"
  depends_on = [terraform_data.images]

  name                   = "backend-api"
  name_prefix            = local.service_defaults.name_prefix
  region                 = local.service_defaults.region
  cluster_name           = local.service_defaults.cluster_name
  capacity_provider_name = local.service_defaults.capacity_provider_name
  execution_role_arn     = local.service_defaults.execution_role_arn
  log_group_prefix       = local.service_defaults.log_group_prefix
  task_role_arn          = module.security.app_role_arns["backend-api"]
  image                  = local.image_urls["backend-api"]

  cpu                = 256
  memory             = 512
  memory_reservation = 256
  container_port     = 8000

  environment = merge(local.common_env, local.db_env, {
    SERVICE_NAME        = "backend-api"
    EMBEDDINGS_PROVIDER = "bedrock"
    ORDERS_QUEUE_URL    = module.sqs.queue_url
    MIGRATE_ON_START    = "true"  # cria as tabelas e carrega o catálogo ao subir
    AUTH_COOKIE_SECURE  = "false" # sem HTTPS por enquanto (decisão do grupo)
  })

  secrets = merge(local.db_secrets, {
    ADMIN_TOKEN     = module.parameters.parameter_arns.admin_token
    AUTH_JWT_SECRET = module.parameters.parameter_arns.auth_jwt_secret
  })

  health_check_command = ["CMD-SHELL", "curl -fsS http://localhost:8000/health || exit 1"]

  # Registrado nos dois ALBs: o público (navegador) e o interno (chatbot).
  load_balancers = [
    module.alb.target_group_arns["backend"],
    module.alb.target_group_arns["backend-int"],
  ]

  min_tasks  = 2
  max_tasks  = 8
  cpu_target = 60
  # Target group INTERNO: é por ele que o chatbot chama o backend, e é onde o
  # tráfego real está (590-632 req/alvo/min contra 0,1 no público). Alvo 1500
  # req/alvo/min veio da medição de 17/11: com 8 tasks a CPU ficou em 14-20%,
  # ou seja, folga demais; 1500 põe o serviço em 3-4 tasks nessa carga.
  #
  # ATENÇÃO À UNIDADE: ALBRequestCountPerTarget é soma por MINUTO, não por
  # segundo. O valor antigo, 60, equivalia a 1 req/s por task — nenhuma
  # aplicação real fica abaixo disso, então a política vivia pedindo o máximo.
  requests_per_target = {
    target         = 1500
    resource_label = module.alb.request_count_labels["backend-int"]
  }
}

# --- chatbot: conversa com o vendedor de IA -------------------------------

module "chatbot" {
  source     = "../modules/ecs-service"
  depends_on = [terraform_data.images]

  name                   = "chatbot"
  name_prefix            = local.service_defaults.name_prefix
  region                 = local.service_defaults.region
  cluster_name           = local.service_defaults.cluster_name
  capacity_provider_name = local.service_defaults.capacity_provider_name
  execution_role_arn     = local.service_defaults.execution_role_arn
  log_group_prefix       = local.service_defaults.log_group_prefix
  task_role_arn          = module.security.app_role_arns["chatbot"]
  image                  = local.image_urls["chatbot"]

  # 512 e não 256: sob carga o chatbot ficou com CPU média entre 72% e 150%
  # sobre uma reserva de 0,25 vCPU, ou seja, saturado mesmo com 8 tasks — era
  # o gargalo do sistema. Medido em 17 e 19/11 (ANALISE.md no repo do backend).
  #
  # Cabe no dimensionamento atual: no pico teórico (chatbot 8x512 + backend
  # 8x256 + worker 6x128 + frontend 2x64 = 7040 unidades) contra 4 t3.small
  # = 8192. Fica apertado; se ecs_max_instances cair de 4, revisar junto.
  cpu                = 512
  memory             = 512
  memory_reservation = 256
  container_port     = 8000

  environment = merge(local.common_env, {
    SERVICE_NAME        = "chatbot"
    LLM_PROVIDER        = "bedrock"
    TABLE_CONVERSATIONS = module.dynamodb.table_name
    BACKEND_URL         = "http://${module.alb.internal_dns_name}"
  })

  secrets = {
    AUTH_JWT_SECRET = module.parameters.parameter_arns.auth_jwt_secret
  }

  health_check_command = ["CMD-SHELL", "curl -fsS http://localhost:8000/health || exit 1"]

  load_balancers = [module.alb.target_group_arns["chatbot"]]

  # Cada mensagem espera a resposta do modelo, por isso o alvo de
  # requisições por task é menor que o do backend.
  min_tasks  = 2
  max_tasks  = 8
  cpu_target = 60
  # Alvo 250: mediu-se ~290 req/alvo/min com 8 tasks. O chatbot é limitado por
  # CPU, não por contagem de requisição — esta política cobre carga leve e
  # numerosa; quem manda, na prática, é a de CPU.
  requests_per_target = {
    target         = 250
    resource_label = module.alb.request_count_labels["chatbot"]
  }
}

# --- order-worker: processa os pedidos da fila -----------------------------

module "order_worker" {
  source     = "../modules/ecs-service"
  depends_on = [terraform_data.images]

  name                   = "order-worker"
  name_prefix            = local.service_defaults.name_prefix
  region                 = local.service_defaults.region
  cluster_name           = local.service_defaults.cluster_name
  capacity_provider_name = local.service_defaults.capacity_provider_name
  execution_role_arn     = local.service_defaults.execution_role_arn
  log_group_prefix       = local.service_defaults.log_group_prefix
  task_role_arn          = module.security.app_role_arns["order-worker"]
  image                  = local.image_urls["order-worker"]

  cpu                = 128
  memory             = 256
  memory_reservation = 128

  environment = merge(local.common_env, local.db_env, {
    SERVICE_NAME        = "order-worker"
    EMBEDDINGS_PROVIDER = "none"
    ORDERS_QUEUE_URL    = module.sqs.queue_url
    WORKER_THREADS      = "2"
    MIGRATE_ON_START    = "false" # quem migra é o backend-api
  })

  secrets = local.db_secrets

  # Sem porta HTTP: o worker atualiza um arquivo a cada ciclo; se ele
  # envelhecer, o loop travou e o ECS troca a task.
  health_check_command      = ["CMD-SHELL", "test -n \"$(find /tmp/heartbeat -mmin -1 2>/dev/null)\" || exit 1"]
  health_check_interval     = 30
  health_check_start_period = 20

  min_tasks = 1
  max_tasks = 6
  sqs_backlog = {
    target     = 20
    queue_name = module.sqs.queue_name
  }
}
