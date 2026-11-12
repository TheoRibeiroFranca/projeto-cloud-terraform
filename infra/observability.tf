module "observability" {
  source = "../modules/observability"

  name_prefix  = local.name_prefix
  region       = var.region
  alarm_emails = var.alarm_emails

  cluster_name           = module.ecs_cluster.cluster_name
  capacity_provider_name = module.ecs_cluster.capacity_provider_name
  asg_name               = module.ecs_cluster.asg_name

  ecs_services = {
    frontend     = module.frontend.service_name
    backend-api  = module.backend_api.service_name
    chatbot      = module.chatbot.service_name
    order-worker = module.order_worker.service_name
  }

  alb_public_arn_suffix   = module.alb.public_arn_suffix
  alb_internal_arn_suffix = module.alb.internal_arn_suffix
  target_groups = {
    for k, suffix in module.alb.target_group_arn_suffixes :
    k => { arn_suffix = suffix, internal = k == "backend-int" }
  }

  orders_queue_name = module.sqs.queue_name
  orders_dlq_name   = module.sqs.dlq_name
  rds_identifier    = module.rds.identifier
}
