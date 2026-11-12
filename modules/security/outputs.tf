output "security_group_ids" {
  description = "IDs dos security groups."
  value = {
    alb          = aws_security_group.alb.id
    alb_internal = aws_security_group.alb_internal.id
    ecs          = aws_security_group.ecs.id
    rds          = aws_security_group.rds.id
  }
}

output "ecs_instance_profile_name" {
  description = "Instance profile usado pelo Launch Template."
  value       = aws_iam_instance_profile.ecs_instance.name
}

output "task_execution_role_arn" {
  description = "Role de execução das tasks."
  value       = aws_iam_role.task_execution.arn
}

output "app_role_arns" {
  description = "Role de aplicação de cada serviço."
  value       = { for k, r in aws_iam_role.app : k => r.arn }
}
