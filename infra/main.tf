module "network" {
  source = "../modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  azs                = local.azs
  single_nat_gateway = var.single_nat_gateway
}

module "security" {
  source = "../modules/security"

  name_prefix    = local.name_prefix
  vpc_id         = module.network.vpc_id
  rds_secret_arn = module.rds.master_secret_arn
  names = {
    ecr_repository_prefix = local.names.ecr_repository_prefix
    log_group_prefix      = local.names.log_group_prefix
    ssm_prefix            = local.names.ssm_prefix
    orders_queue          = local.names.orders_queue
    conversations_table   = local.names.conversations_table
  }
}

# --- Persistência --------------------------------------------------------

module "rds" {
  source = "../modules/rds"

  name_prefix       = local.name_prefix
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.security.security_group_ids.rds
  multi_az          = var.rds_multi_az
}

module "dynamodb" {
  source = "../modules/dynamodb"

  table_name = local.names.conversations_table
}

# --- Mensageria ----------------------------------------------------------

module "sqs" {
  source = "../modules/sqs"

  queue_name = local.names.orders_queue
  dlq_name   = local.names.orders_dlq
}

# --- Parâmetros e segredos das aplicações --------------------------------

module "parameters" {
  source = "../modules/parameters"

  ssm_prefix = local.names.ssm_prefix
}
