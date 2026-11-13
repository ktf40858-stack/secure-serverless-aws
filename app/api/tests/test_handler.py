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


ALICE = "11111111-1111-4111-8111-111111111111"
BOB = "22222222-2222-4222-8222-222222222222"


def event(method, body=None, note_id=None, b64=False, user=ALICE):
    ctx = {"http": {"method": method, "sourceIp": "203.0.113.7"}, "requestId": "req-1"}
    if user is not None:
        ctx["authorizer"] = {"jwt": {"claims": {"sub": user}, "scopes": None}}
    return {
        "requestContext": ctx,
        "pathParameters": {"id": note_id} if note_id else None,
        "body": body,
        "isBase64Encoded": b64,
    }


@pytest.fixture(autouse=True)
def table(monkeypatch):
    with mock_aws():
        boto3.resource("dynamodb").create_table(
            TableName="notes-test",
            KeySchema=[
                {"AttributeName": "owner", "KeyType": "HASH"},
                {"AttributeName": "id", "KeyType": "RANGE"},
            ],
            AttributeDefinitions=[
                {"AttributeName": "owner", "AttributeType": "S"},
                {"AttributeName": "id", "AttributeType": "S"},
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        handler._table = None
        yield


def call(ev):
    return handler.lambda_handler(ev, None)


def create(title="Hello", body="World", user=ALICE):
    res = call(event("POST", json.dumps({"title": title, "body": body}), user=user))
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


# --- Authentication and ownership (threat model S1 / IDOR) ---

@pytest.mark.parametrize("user", [None, "", "not-a-uuid", "../" + ALICE])
def test_requests_without_valid_identity_are_rejected(user):
    for ev in (event("GET", user=user), event("POST", json.dumps({"title": "a", "body": "b"}), user=user)):
        res = call(ev)
        assert res["statusCode"] == 401
        assert json.loads(res["body"]) == {"error": "unauthorized"}


def test_users_only_see_their_own_notes():
    create("alice note", user=ALICE)
    create("bob note", user=BOB)
    alice = json.loads(call(event("GET", user=ALICE))["body"])["notes"]
    assert [n["title"] for n in alice] == ["alice note"]


def test_no_idor_on_read_and_delete():
    _, note = create("secret", user=ALICE)
    # Bob knows the id but gets the same 404 as for a missing note
    assert call(event("GET", note_id=note["id"], user=BOB))["statusCode"] == 404
    assert call(event("DELETE", note_id=note["id"], user=BOB))["statusCode"] == 404
    # Alice's note is untouched
    assert call(event("GET", note_id=note["id"], user=ALICE))["statusCode"] == 200


def test_owner_is_never_returned():
    res, note = create()
    assert "owner" not in note
    assert "owner" not in json.loads(call(event("GET", note_id=note["id"]))["body"])
    assert all("owner" not in n for n in json.loads(call(event("GET"))["body"])["notes"])
