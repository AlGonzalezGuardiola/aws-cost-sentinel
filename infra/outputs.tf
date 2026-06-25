output "lambda_function_name" {
  description = "Name of the Lambda function."
  value       = aws_lambda_function.this.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function."
  value       = aws_lambda_function.this.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS alert topic."
  value       = aws_sns_topic.alerts.arn
}

output "dlq_url" {
  description = "URL of the SQS Dead Letter Queue."
  value       = aws_sqs_queue.dlq.url
}

output "schedule_expression" {
  description = "EventBridge schedule expression in use."
  value       = aws_cloudwatch_event_rule.schedule.schedule_expression
}
