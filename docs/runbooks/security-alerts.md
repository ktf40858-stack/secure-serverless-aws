# Runbooks: security alerts

One page per alert sent to the `secbaseline-security-alerts` SNS topic. Every runbook follows the
same order: **confirm, contain, investigate, recover, close**. All commands assume an admin session
(`aws login --profile lab --region us-east-1`) and read CloudTrail through the console or
`aws cloudtrail lookup-events` (last 90 days of management events).

General first step for every alert:

```bash
# Who did what, from where, in the last hour (replace EventName)
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=<EventName> \
  --start-time "$(date -u -d '-1 hour' +%FT%TZ)" \
  --query "Events[].[EventTime,Username,CloudTrailEvent]" --output text
```

Look at `userIdentity.arn`, `sourceIPAddress`, `userAgent` and whether the call came from the
GitHub deploy role during a pipeline run (expected) or from somewhere else (suspicious).

---

## RB-1 Audit trail changed or stopped (`secbaseline-cloudtrail-changes`)

Triggers on CreateTrail, UpdateTrail, DeleteTrail, StartLogging, StopLogging, PutEventSelectors.
Proven with Stratus Red Team `cloudtrail-stop` and `cloudtrail-event-selectors` (see
[attacks/README.md](../../attacks/README.md)).

1. **Confirm**: `aws cloudtrail get-trail-status --name secbaseline-trail` must show
   `IsLogging: true`; `aws cloudtrail get-event-selectors --trail-name secbaseline-trail` must
   still include management events.
2. **Contain**: `aws cloudtrail start-logging --name secbaseline-trail`, then re-apply the security
   root (`terraform -chdir=terraform/security apply`) to restore the selectors.
3. **Investigate**: stopping logging is a classic first step of an attacker. Treat the actor's
   credentials as compromised: list everything they did in the hour before and after.
4. **Recover**: rotate or delete the actor's credentials (RB-2 step 2).
5. **Close**: note the gap in time without logs in the journal.

## RB-2 IAM policy created, changed or attached (`secbaseline-iam-policy-changes`)

Expected during a Terraform deploy of `notes-dev*` roles; suspicious from any other actor.
Proven with Stratus Red Team `iam-create-admin-user`.

1. **Confirm**: is the actor the deploy role during a pipeline run, or kodjo-admin applying
   Terraform? If yes, close. Otherwise continue.
2. **Contain**: for an unknown user, deactivate its keys first, then remove it:
   ```bash
   aws iam list-access-keys --user-name <user>
   aws iam update-access-key --user-name <user> --access-key-id <id> --status Inactive
   aws iam detach-user-policy --user-name <user> --policy-arn <arn>
   ```
   Delete the user only after the investigation (keys, login profile, policies, then the user).
3. **Investigate**: `lookup-events` with `AttributeKey=Username,AttributeValue=<user>` to see if
   the new keys were used.
4. **Recover**: delete the user; check `aws iam list-users` and `list-roles` for other newcomers.
5. **Close**: journal entry with timeline.

## RB-3 S3 bucket policy or ACL changed (`secbaseline-s3-bucket-policy-changes`)

Proven with Stratus Red Team `s3-backdoor-bucket-policy` (read access granted to an external
account). This one is **not** auto-remediated on purpose: a bucket policy can be legitimate, and an
automatic revert could break the Terraform state bucket or CloudTrail delivery.

1. **Confirm**: `aws s3api get-bucket-policy --bucket <bucket>`. Any `Principal` that is not this
   account, an AWS service of this account, or `aws:SourceAccount`-restricted is suspicious.
2. **Contain**: `aws s3api delete-bucket-policy --bucket <bucket>` for a bucket that should have
   none, or re-apply Terraform for a managed bucket.
3. **Investigate**: S3 data events are only on the Terraform state bucket, so for other buckets
   CloudTrail shows the policy change but not the reads. Check what the bucket holds.
4. **Recover**: if data was readable by the external account, treat it as disclosed.
5. **Close**: journal entry.

## RB-4 Bucket made public (`secbaseline-remediate-s3` alert)

Auto-remediated: the Lambda puts the 4 Block Public Access flags back (18 s in the live test).
Check the alert's actor and IP; if not expected, follow RB-2 steps 2-4 for that actor.

## RB-5 Root used, console login without MFA, failed logins, AccessDenied burst

- **Root used**: nobody should use root. Sign in as root (MFA), check `Security credentials`
  for new keys or MFA devices, change the root password, review the actor IP in CloudTrail.
- **Login without MFA**: the user policy requires MFA; find the user, force a password reset,
  check the MFA device list.
- **3 failed logins**: password guessing. Check the source IP; if unknown and the user is real,
  rotate the password.
- **5 AccessDenied in 5 minutes**: someone probing permissions. Find the principal; a pipeline
  failure after a change is the usual innocent cause.

## RB-6 External access found by IAM Access Analyzer (`secbaseline-external-access` rule)

A resource is shared with another account or the public. Open the finding in the IAM console
(Access Analyzer), check the principal. If intended, archive it with a reason; otherwise remove the
policy statement. Known and accepted: the GitHub OIDC deploy role (federated principal by design).
Limit found in week 4: the analyzer did **not** report the Stratus S3 backdoor within 35 minutes,
so RB-3 is the control for that case.
