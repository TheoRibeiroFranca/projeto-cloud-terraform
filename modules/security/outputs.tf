# Os grupos só saem do módulo com as regras criadas, e o instance profile só
# com as políticas anexadas. Assim as instâncias, os ALBs e o RDS são apagados
# antes das regras e das políticas no destroy. Sem isso, as instâncias perdiam
# a saída 443 e a permissão do ECS, o agente desconectava e os serviços
# travavam em DRAINING.
output "security_group_ids" {
  description = "IDs dos security groups."
  value = {
    alb          = aws_security_group.alb.id
    alb_internal = aws_security_group.alb_internal.id
    ecs          = aws_security_group.ecs.id
    rds          = aws_security_group.rds.id
  }

  depends_on = [
    aws_vpc_security_group_ingress_rule.alb_http,
    aws_vpc_security_group_egress_rule.alb_to_ecs,
    aws_vpc_security_group_ingress_rule.alb_internal_from_ecs,
    aws_vpc_security_group_egress_rule.alb_internal_to_ecs,
    aws_vpc_security_group_ingress_rule.ecs_from_alb,
    aws_vpc_security_group_egress_rule.ecs_to_alb_internal,
    aws_vpc_security_group_egress_rule.ecs_to_rds,
    aws_vpc_security_group_egress_rule.ecs_https,
    aws_vpc_security_group_ingress_rule.rds_from_ecs,
  ]
}

output "ecs_instance_profile_name" {
  description = "Instance profile usado pelo Launch Template."
  value       = aws_iam_instance_profile.ecs_instance.name

  depends_on = [aws_iam_role_policy_attachment.ecs_instance]
}

# As roles só saem do módulo depois que as políticas estão anexadas. Sem isso,
# o ECS pode iniciar tasks com uma role ainda sem permissões (aconteceu no
# primeiro apply: as tasks não conseguiram baixar imagens nem ler segredos).
output "task_execution_role_arn" {
  description = "Role de execução das tasks."
  value       = aws_iam_role.task_execution.arn

  depends_on = [aws_iam_role_policy.task_execution]
}

output "app_role_arns" {
  description = "Role de aplicação de cada serviço."
  value       = { for k, r in aws_iam_role.app : k => r.arn }

  depends_on = [aws_iam_role_policy.app]
}
