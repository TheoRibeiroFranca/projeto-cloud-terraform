module "network" {
  source = "../modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  azs                = local.azs
  single_nat_gateway = var.single_nat_gateway
}

module "security" {
  source = "../modules/security"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
  names = {
    ecr_repository_prefix = local.names.ecr_repository_prefix
    log_group_prefix      = local.names.log_group_prefix
    ssm_prefix            = local.names.ssm_prefix
    rds_secret_name       = local.names.rds_secret_name
    orders_queue          = local.names.orders_queue
    conversations_table   = local.names.conversations_table
  }
}
