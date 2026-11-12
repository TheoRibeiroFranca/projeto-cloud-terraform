output "alarm_topic_arn" {
  description = "Tópico SNS dos alarmes."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_count" {
  description = "Quantidade de alarmes criados."
  value       = length(local.all_alarm_arns)
}

output "dashboard_url" {
  description = "Endereço do dashboard no console."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.this.dashboard_name}"
}
