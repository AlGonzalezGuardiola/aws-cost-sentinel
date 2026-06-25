# ── Lambda package ────────────────────────────────────────────────────────────

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/sentinel.py"
  output_path = "${path.module}/../lambda/sentinel.zip"
}

# ── SNS topic ─────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  # checkov:skip=CKV_AWS_26:AWS-managed key encryption acceptable for this use case
  name = "${var.name}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Dead Letter Queue ─────────────────────────────────────────────────────────

resource "aws_sqs_queue" "dlq" {
  # checkov:skip=CKV_AWS_27:AWS-managed key encryption acceptable for this use case
  name                      = "${var.name}-dlq"
  message_retention_seconds = 86400
  tags                      = var.tags
}

# ── CloudWatch log group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda" {
  # checkov:skip=CKV_AWS_158:AWS-managed key encryption acceptable for this use case
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ── IAM role ──────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${var.name}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  # checkov:skip=CKV_AWS_290:Cost Explorer and STS do not support resource-level permissions
  # checkov:skip=CKV_AWS_355:Cost Explorer and STS do not support resource-level permissions
  name = "${var.name}-lambda"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CostExplorer"
        Effect   = "Allow"
        Action   = ["ce:GetCostAndUsage"]
        Resource = ["*"]
      },
      {
        Sid      = "STSIdentity"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = ["*"]
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.alerts.arn]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = [
          aws_cloudwatch_log_group.lambda.arn,
          "${aws_cloudwatch_log_group.lambda.arn}:log-stream:*",
        ]
      },
      {
        Sid      = "SQSDLQSend"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.dlq.arn]
      },
    ]
  })
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "this" {
  # checkov:skip=CKV_AWS_272:Code signing not required for internal tooling
  # checkov:skip=CKV_AWS_117:VPC not required — function only calls AWS APIs
  # checkov:skip=CKV_AWS_158:AWS-managed key encryption acceptable for this use case
  # checkov:skip=CKV_AWS_173:AWS-managed key encryption acceptable for this use case
  function_name = var.name
  role          = aws_iam_role.lambda.arn
  handler       = "sentinel.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      BUDGET_THRESHOLD  = tostring(var.budget_threshold_usd)
      SNS_TOPIC_ARN     = aws_sns_topic.alerts.arn
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = var.tags
}

# ── EventBridge schedule ──────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "schedule" {
  # checkov:skip=CKV_AWS_49:Event bus policy not required for Lambda targets
  name                = var.name
  description         = "Daily AWS cost threshold check"
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = var.name
  arn       = aws_lambda_function.this.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
