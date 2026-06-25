# aws-cost-sentinel

Lambda function that monitors your AWS monthly spend and fires alerts (SNS email and/or Slack) when it crosses a configured threshold. Deployed with Terraform and triggered daily via EventBridge.

## How it works

```
EventBridge (cron)
       │
       ▼
  Lambda (Python 3.12)
  sentinel.handler
       │
       ├── boto3 → Cost Explorer → get current month UnblendedCost
       │
       ├── if spend ≥ threshold → SNS topic → email subscription
       │
       └── if slack_webhook_url set → POST to Slack
```

## Deployment

```bash
cd infra

# Create a terraform.tfvars
cat > terraform.tfvars <<EOF
budget_threshold_usd = 50
alert_email          = "you@example.com"
EOF

terraform init
terraform apply
```

## Configuration

| Variable | Description | Default |
|---|---|---|
| `budget_threshold_usd` | Monthly spend alert threshold (USD) | **required** |
| `alert_email` | Email to subscribe to SNS alerts | `""` (disabled) |
| `slack_webhook_url` | Slack incoming webhook URL | `""` (disabled) |
| `schedule_expression` | EventBridge cron | `cron(0 8 * * ? *)` (daily 08:00 UTC) |
| `lambda_reserved_concurrency` | Reserved Lambda concurrency | `5` |
| `log_retention_days` | CloudWatch log retention | `365` |
| `aws_region` | AWS region | `eu-west-1` |

## Infrastructure

- **Lambda** — Python 3.12, X-Ray tracing enabled, SQS Dead Letter Queue
- **SNS topic** — alert delivery, optional email subscription
- **EventBridge rule** — daily scheduled trigger
- **IAM role** — least-privilege: Cost Explorer read, SNS publish, CloudWatch Logs write
- **CloudWatch log group** — 365-day retention

## Local development

```bash
# Install dev dependencies
pip install -r lambda/requirements-dev.txt

# Run tests
pytest lambda/tests/ -v
```

## License

MIT
