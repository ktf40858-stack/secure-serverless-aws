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

import remediate_s3  # noqa: E402

ACCOUNT = "123456789012"
BUCKET = "victim-bucket"


def ct_event(name, bucket=BUCKET):
    params = {"bucketName": bucket} if bucket else {}
    return {
        "account": ACCOUNT,
        "detail": {
            "eventName": name,
            "eventTime": "2026-11-12T00:00:00Z",
            "sourceIPAddress": "198.51.100.9",
            "recipientAccountId": ACCOUNT,
            "userIdentity": {"arn": f"arn:aws:iam::{ACCOUNT}:user/attacker"},
            "requestParameters": params,
        },
    }


@pytest.fixture
def aws(monkeypatch):
    with mock_aws():
        s3 = boto3.client("s3")
        s3.create_bucket(Bucket=BUCKET)
        topic = boto3.client("sns").create_topic(Name="alerts")["TopicArn"]
        sqs = boto3.client("sqs")
        q = sqs.create_queue(QueueName="inbox")["QueueUrl"]
        q_arn = sqs.get_queue_attributes(QueueUrl=q, AttributeNames=["QueueArn"])["Attributes"]["QueueArn"]
        boto3.client("sns").subscribe(TopicArn=topic, Protocol="sqs", Endpoint=q_arn)
        monkeypatch.setenv("ALERT_TOPIC_ARN", topic)
        yield {"s3": s3, "sqs": sqs, "queue": q}


def alerts(aws):
    msgs = aws["sqs"].receive_message(QueueUrl=aws["queue"], MaxNumberOfMessages=10).get("Messages", [])
    return [json.loads(json.loads(m["Body"])["Message"]) for m in msgs]


def test_bucket_without_block_is_fixed_and_alerted(aws):
    res = remediate_s3.lambda_handler(ct_event("DeleteBucketPublicAccessBlock"), None)
    assert res == {"remediated": True, "target": f"bucket:{BUCKET}"}
    cfg = aws["s3"].get_public_access_block(Bucket=BUCKET)["PublicAccessBlockConfiguration"]
    assert all(cfg.values())
    sent = alerts(aws)
    assert len(sent) == 1
    assert sent[0]["actor"].endswith(":user/attacker")
    assert sent[0]["source_ip"] == "198.51.100.9"


def test_partially_weakened_bucket_is_fixed(aws):
    aws["s3"].put_public_access_block(Bucket=BUCKET, PublicAccessBlockConfiguration={
        "BlockPublicAcls": True, "IgnorePublicAcls": True,
        "BlockPublicPolicy": False, "RestrictPublicBuckets": True,
    })
    assert remediate_s3.lambda_handler(ct_event("PutBucketPublicAccessBlock"), None)["remediated"] is True


def test_already_blocked_bucket_is_left_alone_no_loop(aws):
    aws["s3"].put_public_access_block(Bucket=BUCKET, PublicAccessBlockConfiguration=remediate_s3.FULL_BLOCK)
    assert remediate_s3.lambda_handler(ct_event("PutBucketPublicAccessBlock"), None) == {"remediated": False}
    assert alerts(aws) == []


def test_event_without_bucket_is_ignored(aws):
    assert remediate_s3.lambda_handler(ct_event("PutBucketPolicy", bucket=None), None) == {"remediated": False}


def test_deleted_bucket_is_ignored(aws):
    assert remediate_s3.lambda_handler(ct_event("PutBucketPolicy", bucket="gone-bucket"), None) == {"remediated": False}


def test_account_level_block_is_restored(aws):
    res = remediate_s3.lambda_handler(ct_event("DeleteAccountPublicAccessBlock", bucket=None), None)
    assert res == {"remediated": True, "target": f"account:{ACCOUNT}"}
    cfg = boto3.client("s3control").get_public_access_block(AccountId=ACCOUNT)["PublicAccessBlockConfiguration"]
    assert all(cfg.values())
