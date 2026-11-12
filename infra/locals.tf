data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Zonas da região que oferecem o tipo de instância do cluster.
data "aws_ec2_instance_type_offerings" "ecs" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.ecs_instance_type]
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id

  # Nada fixo de Ohio: as zonas vêm da região e do tipo de instância.
  supported_azs = sort([
    for az in data.aws_availability_zones.available.names : az
    if contains(data.aws_ec2_instance_type_offerings.ecs.locations, az)
  ])
  azs = slice(local.supported_azs, 0, var.az_count)
}
