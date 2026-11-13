"""Auto-remediation: put S3 Block Public Access back as soon as someone weakens it.

Trigger: EventBridge rule on CloudTrail events from s3.amazonaws.com (bucket policy, ACL,
public access block changes at bucket or account level).

What it does:
- reads the real current setting (never trusts the event content alone)
- if any of the 4 Block Public Access flags is off, turns all 4 back on
- sends one alert to SNS with who did it, from where, and what was fixed

Safe to run twice: when everything is already blocked, it does nothing. Its own fix produces a new
CloudTrail event that triggers it again, finds nothing to fix, and stops (no loop).
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

FULL_BLOCK = {
    "BlockPublicAcls": True,
    "IgnorePublicAcls": True,
    "BlockPublicPolicy": True,
    "RestrictPublicBuckets": True,
}
ACCOUNT_EVENTS = {"PutAccountPublicAccessBlock", "DeleteAccountPublicAccessBlock"}


def _is_full(config):
    return all(config.get(k) is True for k in FULL_BLOCK)


def _bucket_config(s3, bucket):
    try:
        return s3.get_public_access_block(Bucket=bucket)["PublicAccessBlockConfiguration"]
    except ClientError as err:
        if err.response["Error"]["Code"] == "NoSuchPublicAccessBlockConfiguration":
            return {}
        raise


def _account_config(s3control, account):
    try:
        return s3control.get_public_access_block(AccountId=account)["PublicAccessBlockConfiguration"]
    except ClientError as err:
        if err.response["Error"]["Code"] == "NoSuchPublicAccessBlockConfiguration":
            return {}
        raise


def _alert(target, before, detail):
    identity = detail.get("userIdentity", {})
    message = {
        "alert": "S3 Block Public Access was weakened and has been restored automatically",
        "target": target,
        "event": detail.get("eventName"),
        "actor": identity.get("arn"),
        "source_ip": detail.get("sourceIPAddress"),
        "event_time": detail.get("eventTime"),
        "setting_before": before,
        "setting_after": FULL_BLOCK,
    }
    boto3.client("sns").publish(
        TopicArn=os.environ["ALERT_TOPIC_ARN"],
        Subject="[secure-serverless] S3 public access auto-remediated",
        Message=json.dumps(message, indent=2),
    )
    return message


def lambda_handler(event, context):
    detail = event.get("detail", {})
    name = detail.get("eventName", "")

    if name in ACCOUNT_EVENTS:
        account = detail.get("recipientAccountId") or event.get("account")
        s3control = boto3.client("s3control")
        before = _account_config(s3control, account)
        if _is_full(before):
            LOG.info(json.dumps({"action": "noop", "target": f"account:{account}", "event": name}))
            return {"remediated": False}
        s3control.put_public_access_block(AccountId=account, PublicAccessBlockConfiguration=FULL_BLOCK)
        msg = _alert(f"account:{account}", before, detail)
        LOG.warning(json.dumps({"action": "remediated", **msg}))
        return {"remediated": True, "target": f"account:{account}"}

    bucket = (detail.get("requestParameters") or {}).get("bucketName")
    if not isinstance(bucket, str) or not bucket:
        LOG.info(json.dumps({"action": "ignored", "reason": "no bucket in event", "event": name}))
        return {"remediated": False}

    s3 = boto3.client("s3")
    try:
        before = _bucket_config(s3, bucket)
    except ClientError as err:
        # Bucket deleted in the meantime, or owned by someone else: nothing to fix here.
        if err.response["Error"]["Code"] in ("NoSuchBucket", "AccessDenied"):
            LOG.info(json.dumps({"action": "ignored", "reason": err.response["Error"]["Code"], "bucket": bucket}))
            return {"remediated": False}
        raise

    if _is_full(before):
        LOG.info(json.dumps({"action": "noop", "target": f"bucket:{bucket}", "event": name}))
        return {"remediated": False}

    s3.put_public_access_block(Bucket=bucket, PublicAccessBlockConfiguration=FULL_BLOCK)
    msg = _alert(f"bucket:{bucket}", before, detail)
    LOG.warning(json.dumps({"action": "remediated", **msg}))
    return {"remediated": True, "target": f"bucket:{bucket}"}
