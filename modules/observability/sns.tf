# Tópico que recebe todos os alarmes. Quem assina recebe o aviso quando um
# alarme dispara e quando ele volta ao normal.
#
# Sem criptografia com a chave gerenciada aws/sns de propósito: a política
# dessa chave não deixa o CloudWatch publicar, e os alarmes falhariam calados.
# Os avisos não carregam dados sensíveis.

resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
}

data "aws_iam_policy_document" "alarms_topic" {
  statement {
    sid     = "CloudWatchAlarms"
    actions = ["sns:Publish"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    resources = [aws_sns_topic.alarms.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarms_topic.json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alarm_emails)

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}
