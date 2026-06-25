import json
import logging
import os
import urllib.request
from datetime import date

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def get_month_cost(ce_client) -> tuple[float, str]:
    today = date.today()
    start = today.replace(day=1).isoformat()
    end = today.isoformat()

    if start == end:
        return 0.0, "USD"

    response = ce_client.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
        Metrics=["UnblendedCost"],
    )
    result = response["ResultsByTime"][0]["Total"]["UnblendedCost"]
    return float(result["Amount"]), result["Unit"]


def build_message(amount: float, unit: str, threshold: float, account_id: str) -> str:
    status = "ALERT" if amount >= threshold else "OK"
    period = date.today().strftime("%B %Y")
    return (
        f"[aws-cost-sentinel] {status}\n"
        f"Account:   {account_id}\n"
        f"Period:    {period}\n"
        f"Spend:     {amount:.2f} {unit}\n"
        f"Threshold: {threshold:.2f} {unit}\n"
    )


def publish_sns(sns_client, topic_arn: str, subject: str, message: str) -> None:
    sns_client.publish(TopicArn=topic_arn, Subject=subject, Message=message)
    logger.info("SNS alert sent to %s", topic_arn)


def publish_slack(webhook_url: str, message: str) -> None:
    payload = json.dumps({"text": f"```{message}```"}).encode()
    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    urllib.request.urlopen(req, timeout=5)  # noqa: S310
    logger.info("Slack alert sent")


def handler(event, context):
    threshold = float(os.environ["BUDGET_THRESHOLD"])
    sns_topic_arn = os.environ.get("SNS_TOPIC_ARN", "")
    slack_webhook = os.environ.get("SLACK_WEBHOOK_URL", "")

    ce = boto3.client("ce", region_name="us-east-1")
    sts = boto3.client("sts")

    account_id = sts.get_caller_identity()["Account"]
    amount, unit = get_month_cost(ce)

    logger.info("Cost: %.2f %s | Threshold: %.2f %s", amount, unit, threshold, unit)

    alert_triggered = amount >= threshold

    if alert_triggered:
        subject = f"[aws-cost-sentinel] Spend alert: {amount:.2f} {unit}"
        message = build_message(amount, unit, threshold, account_id)

        if sns_topic_arn:
            publish_sns(boto3.client("sns"), sns_topic_arn, subject, message)

        if slack_webhook:
            publish_slack(slack_webhook, message)

    return {
        "statusCode": 200,
        "account_id": account_id,
        "amount": round(amount, 2),
        "unit": unit,
        "threshold": threshold,
        "alert_triggered": alert_triggered,
    }
