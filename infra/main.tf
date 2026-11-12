module "network" {
  source = "../modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  azs                = local.azs
  single_nat_gateway = var.single_nat_gateway
}
