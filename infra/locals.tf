data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id

  # As zonas vêm da região, sem nada fixo de Ohio.
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}
