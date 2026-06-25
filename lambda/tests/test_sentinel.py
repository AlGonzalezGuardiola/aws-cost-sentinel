import os
from unittest.mock import MagicMock, patch

import pytest

os.environ.setdefault("BUDGET_THRESHOLD", "100")
os.environ.setdefault("SNS_TOPIC_ARN", "arn:aws:sns:eu-west-1:123456789012:alerts")
os.environ.setdefault("AWS_DEFAULT_REGION", "eu-west-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")

import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sentinel import build_message, handler


CE_RESPONSE = {
    "ResultsByTime": [
        {"Total": {"UnblendedCost": {"Amount": "{}", "Unit": "USD"}}}
    ]
}


def _make_ce(amount: str) -> MagicMock:
    mock = MagicMock()
    response = {
        "ResultsByTime": [
            {"Total": {"UnblendedCost": {"Amount": amount, "Unit": "USD"}}}
        ]
    }
    mock.get_cost_and_usage.return_value = response
    return mock


def _make_sts(account: str = "123456789012") -> MagicMock:
    mock = MagicMock()
    mock.get_caller_identity.return_value = {"Account": account}
    return mock


def test_build_message_alert():
    msg = build_message(150.0, "USD", 100.0, "123456789012")
    assert "ALERT" in msg
    assert "150.00 USD" in msg
    assert "100.00 USD" in msg
    assert "123456789012" in msg


def test_build_message_ok():
    msg = build_message(50.0, "USD", 100.0, "123456789012")
    assert "OK" in msg
    assert "50.00 USD" in msg


def test_handler_below_threshold(monkeypatch):
    monkeypatch.setenv("BUDGET_THRESHOLD", "500")
    monkeypatch.setenv("SNS_TOPIC_ARN", "")

    mock_ce = _make_ce("42.50")
    mock_sts = _make_sts()

    def _client(service, **kw):
        return mock_ce if service == "ce" else mock_sts

    with patch("boto3.client", side_effect=_client):
        result = handler({}, {})

    assert result["alert_triggered"] is False
    assert result["amount"] == 42.5
    assert result["threshold"] == 500.0


def test_handler_above_threshold_triggers_sns(monkeypatch):
    monkeypatch.setenv("BUDGET_THRESHOLD", "10")
    monkeypatch.setenv("SNS_TOPIC_ARN", "arn:aws:sns:eu-west-1:123456789012:alerts")
    monkeypatch.setenv("SLACK_WEBHOOK_URL", "")

    mock_ce = _make_ce("99.99")
    mock_sts = _make_sts()
    mock_sns = MagicMock()

    def _client(service, **kw):
        return {"ce": mock_ce, "sts": mock_sts, "sns": mock_sns}.get(service, MagicMock())

    with patch("boto3.client", side_effect=_client):
        result = handler({}, {})

    assert result["alert_triggered"] is True
    mock_sns.publish.assert_called_once()
    call_kwargs = mock_sns.publish.call_args[1]
    assert "ALERT" in call_kwargs["Subject"] or "alert" in call_kwargs["Subject"].lower()


def test_handler_no_sns_when_empty(monkeypatch):
    monkeypatch.setenv("BUDGET_THRESHOLD", "10")
    monkeypatch.setenv("SNS_TOPIC_ARN", "")
    monkeypatch.setenv("SLACK_WEBHOOK_URL", "")

    mock_ce = _make_ce("999.00")
    mock_sts = _make_sts()
    mock_sns = MagicMock()

    def _client(service, **kw):
        return {"ce": mock_ce, "sts": mock_sts, "sns": mock_sns}.get(service, MagicMock())

    with patch("boto3.client", side_effect=_client):
        result = handler({}, {})

    assert result["alert_triggered"] is True
    mock_sns.publish.assert_not_called()
