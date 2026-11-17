# Attack simulation with Stratus Red Team

**Date:** 2026-11-17 (UTC). **Tool:** [Stratus Red Team](https://github.com/DataDog/stratus-red-team)
v2.37.2 (Windows build, SHA-256 checked against the release checksums). **Target:** the live lab
account, region us-east-1. **Goal:** check that the week 3 detections actually fire on real attacker
behaviour, not only in unit tests.

Each technique was detonated, observed, then cleaned up with `stratus cleanup`. The admin IAM user
created by the persistence technique was removed right after detonation; its CloudTrail events
were already recorded, so no evidence was lost. Account IDs and key IDs are redacted in the
evidence files.

## Results

| # | Technique | MITRE ATT&CK | What it does | Expected detection | Detected? | Time to alert |
|---|---|---|---|---|---|---|
| 1 | `aws.persistence.iam-create-admin-user` | T1136.003 Create Cloud Account | Creates `malicious-iam-user`, attaches AdministratorAccess, creates an access key | Alarm `iam-policy-changes` (AttachUserPolicy) | Yes | ~3 min (event 00:59:08, alarm 01:02:30) |
| 2 | `aws.defense-evasion.cloudtrail-stop` | T1562.008 Disable Cloud Logs | Stops a CloudTrail trail | Alarm `cloudtrail-changes` (StopLogging) | Yes | ~80 s (event 01:00:21, alarm 01:01:45) |
| 3 | `aws.defense-evasion.cloudtrail-event-selectors` | T1562.008 Disable Cloud Logs | Event selectors that drop management and data events (the trail still says "logging") | Alarm `cloudtrail-changes` (PutEventSelectors) | Yes (same alarm, already in ALARM) | CloudTrail event 01:01:12 matched the filter |
| 4 | `aws.exfiltration.s3-backdoor-bucket-policy` | T1530 Data from Cloud Storage | Bucket policy granting `s3:GetObject`/`ListBucket` to an external AWS account | None existed | **No** (gap) | n/a |
| 4b | Same technique after the fix | | | Alarm `s3-bucket-policy-changes` (new) | **Yes** | ~67 s (event 02:07:58, alarm 02:09:05, alarm was OK before) |

## The gap (technique 4) and how it was fixed

1. **What happened.** The S3 auto-remediation Lambda received the `PutBucketPolicy` event and
   logged `"action": "noop"` (evidence: `docs/evidence/week4-stratus/remediation-lambda-noop.log`).
   That is correct for what it was built for: it restores Block Public Access, and a policy that
   names one external account is not "public". None of the 8 alarms matched either.
2. **First fix tried: IAM Access Analyzer.** The account analyzer is designed to flag resources
   shared outside the account, so its findings were wired to SNS through EventBridge
   (`terraform/security/external_access.tf`). Re-ran the attack: the analyzer did analyze the
   bucket (`lastResourceAnalyzed` = the backdoored bucket) but raised **no finding after
   35 minutes**. The rule is kept for the other resource types, but it did not solve this case.
   Lesson: a control is not real until an attack has triggered it.
3. **Fix that works: CIS 4.8 alarm.** Metric filter on S3 `PutBucketPolicy`, `DeleteBucketPolicy`,
   `PutBucketAcl`, CORS, lifecycle and replication changes -> alarm -> SNS. 9 alarms, still in the
   free tier. Response is manual on purpose ([runbook RB-3](../docs/runbooks/security-alerts.md)):
   a bucket policy can be legitimate, and an automatic revert could break the Terraform state or
   CloudTrail buckets.
4. **Re-test.** The first re-run fired the alarm 3 seconds *before* the backdoor, because Stratus's
   own setup (creating the bucket) also matches the filter. That proves nothing about the attack,
   so the test was redone cleanly: revert, wait for the alarm to return to OK, then detonate only
   the backdoor step. Result in the table above (row 4b).

## Evidence

`docs/evidence/week4-stratus/`:

- `cloudtrail-attack-events.json`: the attack events from CloudTrail (CreateUser, AttachUserPolicy,
  CreateAccessKey, StopLogging, PutEventSelectors, PutBucketPolicy) with timestamps.
- `alarm-*.json`: CloudWatch alarm state history (OK -> ALARM) for each detection.
- `remediation-lambda-noop.log`: the remediation Lambda seeing the backdoor and doing nothing.

## Limits of this test

- Alerts were sent to SNS; email delivery depends on the subscription being confirmed.
- Only 4 techniques out of the AWS catalogue were run, chosen to match the controls built in
  week 3. Credential access, EC2 and Lambda persistence techniques were not tested.
- Detection time depends on CloudTrail delivery to CloudWatch Logs (usually 1 to 5 minutes).
