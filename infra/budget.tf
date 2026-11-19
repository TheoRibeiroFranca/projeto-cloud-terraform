# Orçamento mensal do ambiente desta região.
#
# O filtro é por região, e não pela tag Project: a conta faz parte de uma
# organização, e só a conta pagadora ativa tags de custo. Sem a tag ativada, um
# filtro por tag mediria zero. A região separa este ambiente do de Ohio.
#
# Os avisos (80% do gasto real e 100% do previsto) só existem com e-mails em
# var.alarm_emails; sem eles, o orçamento só aparece no console do Billing.

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Region"
    values = [var.region]
  }

  dynamic "notification" {
    for_each = length(var.alarm_emails) > 0 ? {
      ACTUAL     = 80
      FORECASTED = 100
    } : {}

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.key
      subscriber_email_addresses = var.alarm_emails
    }
  }
}
