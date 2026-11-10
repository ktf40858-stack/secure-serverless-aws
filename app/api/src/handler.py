"""Notes API: a small CRUD service used as the target of the security lab.

Routes (HTTP API payload v2):
    GET    /notes          list notes (max 50)
    POST   /notes          create a note  {"title": str, "body": str}
    GET    /notes/{id}     read one note
    DELETE /notes/{id}     delete one note

Security choices:
- strict input validation (types, lengths, allowed keys, body size)
- no stack traces or internal details in responses
- structured JSON logs without the note content
- the table name comes from the environment, never from the request
"""

import json
import logging
import os
import re
import time
import uuid
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

MAX_BODY_BYTES = 4096
MAX_TITLE = 120
MAX_TEXT = 2000
LIST_LIMIT = 50
ID_PATTERN = re.compile(r"^[0-9a-f]{32}$")
ALLOWED_FIELDS = {"title", "body"}

SECURITY_HEADERS = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Strict-Transport-Security": "max-age=63072000; includeSubDomains",
}

_table = None


def _get_table():
    global _table
    if _table is None:
        _table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    return _table


def _json_default(value):
    # DynamoDB returns numbers as Decimal, which json cannot serialise by default
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    raise TypeError(f"not serialisable: {type(value).__name__}")


def _response(status, payload):
    return {
        "statusCode": status,
        "headers": SECURITY_HEADERS,
        "body": json.dumps(payload, default=_json_default),
    }


def _log(event, status, action):
    ctx = event.get("requestContext", {})
    LOG.info(json.dumps({
        "action": action,
        "status": status,
        "request_id": ctx.get("requestId"),
        "source_ip": ctx.get("http", {}).get("sourceIp"),
    }))


def _parse_note(event):
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        return None, "base64 bodies are not accepted"
    if len(raw.encode("utf-8")) > MAX_BODY_BYTES:
        return None, "body too large"
    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        return None, "body must be valid JSON"
    if not isinstance(data, dict):
        return None, "body must be a JSON object"
    if set(data) - ALLOWED_FIELDS:
        return None, "unexpected fields"
    title, body = data.get("title"), data.get("body")
    if not isinstance(title, str) or not title.strip() or len(title) > MAX_TITLE:
        return None, f"title must be a non-empty string of at most {MAX_TITLE} characters"
    if not isinstance(body, str) or len(body) > MAX_TEXT:
        return None, f"body must be a string of at most {MAX_TEXT} characters"
    return {"title": title.strip(), "body": body}, None


def _route(event):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    note_id = (event.get("pathParameters") or {}).get("id")

    if note_id is not None and not ID_PATTERN.match(note_id):
        return 400, {"error": "invalid id"}, "bad_id"

    table = _get_table()

    if method == "GET" and note_id is None:
        items = table.scan(Limit=LIST_LIMIT).get("Items", [])
        return 200, {"notes": items}, "list"

    if method == "POST" and note_id is None:
        note, error = _parse_note(event)
        if error:
            return 400, {"error": error}, "create_rejected"
        note["id"] = uuid.uuid4().hex
        note["created_at"] = int(time.time())
        table.put_item(Item=note, ConditionExpression="attribute_not_exists(id)")
        return 201, note, "create"

    if method == "GET":
        item = table.get_item(Key={"id": note_id}).get("Item")
        if not item:
            return 404, {"error": "not found"}, "read_missing"
        return 200, item, "read"

    if method == "DELETE" and note_id is not None:
        try:
            table.delete_item(Key={"id": note_id}, ConditionExpression="attribute_exists(id)")
        except ClientError as err:
            if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return 404, {"error": "not found"}, "delete_missing"
            raise
        return 204, {}, "delete"

    return 405, {"error": "method not allowed"}, "method_rejected"


def lambda_handler(event, context):
    try:
        status, payload, action = _route(event)
    except Exception:  # never leak internals to the caller
        LOG.exception("unhandled error")
        status, payload, action = 500, {"error": "internal error"}, "error"
    _log(event, status, action)
    if status == 204:
        return {"statusCode": 204, "headers": SECURITY_HEADERS, "body": ""}
    return _response(status, payload)
