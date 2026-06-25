variable "name" {
  description = "Name prefix applied to all resources."
  type        = string
  default     = "aws-cost-sentinel"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "budget_threshold_usd" {
  description = "Monthly spend threshold in USD. An alert fires when current spend reaches this value."
  type        = number

  validation {
    condition     = var.budget_threshold_usd > 0
    error_message = "budget_threshold_usd must be greater than 0."
  }
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for the daily cost check."
  type        = string
  default     = "cron(0 8 * * ? *)"
}

variable "alert_email" {
  description = "Email address to subscribe to the SNS alert topic. Leave empty to skip."
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL. Leave empty to skip. Marked sensitive."
  type        = string
  default     = ""
  sensitive   = true
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for the Lambda function. -1 means unreserved."
  type        = number
  default     = 5
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
