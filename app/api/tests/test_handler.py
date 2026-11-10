import json
import os
import sys

import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
os.environ["TABLE_NAME"] = "notes-test"

import handler  # noqa: E402


def event(method, body=None, note_id=None, b64=False):
    return {
        "requestContext": {"http": {"method": method, "sourceIp": "203.0.113.7"}, "requestId": "req-1"},
        "pathParameters": {"id": note_id} if note_id else None,
        "body": body,
        "isBase64Encoded": b64,
    }


@pytest.fixture(autouse=True)
def table(monkeypatch):
    with mock_aws():
        boto3.resource("dynamodb").create_table(
            TableName="notes-test",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        handler._table = None
        yield


def call(ev):
    return handler.lambda_handler(ev, None)


def create(title="Hello", body="World"):
    res = call(event("POST", json.dumps({"title": title, "body": body})))
    return res, json.loads(res["body"])


def test_create_read_delete_cycle():
    res, note = create()
    assert res["statusCode"] == 201
    got = call(event("GET", note_id=note["id"]))
    assert got["statusCode"] == 200
    assert json.loads(got["body"])["title"] == "Hello"
    assert call(event("DELETE", note_id=note["id"]))["statusCode"] == 204
    assert call(event("GET", note_id=note["id"]))["statusCode"] == 404


def test_list():
    create()
    create("Second")
    res = call(event("GET"))
    assert res["statusCode"] == 200
    assert len(json.loads(res["body"])["notes"]) == 2


@pytest.mark.parametrize("payload", [
    "not json",
    json.dumps([1, 2]),
    json.dumps({"title": "", "body": "x"}),
    json.dumps({"title": "x" * 121, "body": "x"}),
    json.dumps({"title": "ok", "body": "x" * 2001}),
    json.dumps({"title": "ok", "body": "x", "admin": True}),
    json.dumps({"title": 5, "body": "x"}),
])
def test_rejects_bad_input(payload):
    assert call(event("POST", payload))["statusCode"] == 400


def test_rejects_oversized_and_base64_bodies():
    assert call(event("POST", "x" * 5000))["statusCode"] == 400
    assert call(event("POST", "e30=", b64=True))["statusCode"] == 400


@pytest.mark.parametrize("bad_id", ["../etc/passwd", "1 OR 1=1", "abc", "A" * 32])
def test_rejects_bad_ids(bad_id):
    assert call(event("GET", note_id=bad_id))["statusCode"] == 400


def test_unknown_method_and_missing_delete():
    assert call(event("PATCH"))["statusCode"] == 405
    assert call(event("DELETE", note_id="0" * 32))["statusCode"] == 404


def test_errors_do_not_leak_internals(monkeypatch):
    monkeypatch.setenv("TABLE_NAME", "does-not-exist")
    handler._table = None
    res = call(event("GET"))
    assert res["statusCode"] == 500
    assert json.loads(res["body"]) == {"error": "internal error"}


def test_security_headers_present():
    res, _ = create()
    assert res["headers"]["X-Content-Type-Options"] == "nosniff"
    assert res["headers"]["Cache-Control"] == "no-store"
