# CIS AWS Foundations v1.4 Level 1 - score before / after

Measured with AWS Config and the official AWS conformance pack
(`terraform/security/conformance/`), on 2026-11-12, account with the notes API, the pipeline and
the security baseline deployed. Only the 21 automated rules that had resources to evaluate are
counted; 18 manual process checks and rules with nothing to check (RDS, EBS volumes) are listed
apart.

| | Compliant | Non compliant | Score |
|---|---|---|---|
| Before | 14 | 7 | **67 %** |
| After  | 18 | 3 | **86 %** |

## What was fixed (terraform/security/cis_fixes.tf, all free)

| Rule | CIS | Before | Fix |
|---|---|---|---|
| iam-password-policy | 1.8-1.9 | No account password policy | 14 chars, 4 character types, 24 reuse prevention, 90-day age |
| ec2-ebs-encryption-by-default | 2.2.1 | Off | On for the region |
| iam-policy-in-use (AWSSupportAccess) | 1.17 | No support role | `secbaseline-aws-support` role, assumable only with MFA |
| iam-user-no-policies-check | 1.15 | `IAMUserChangePassword` attached directly to the admin user (console default) | Detached; the user gets rights only from its group |
| iam-access-analyzer-enabled | 1.20 | No analyzer | Account analyzer (periodic rule, result pending at time of writing) |

## What stays non compliant, on purpose

| Rule | Why it is accepted |
|---|---|
| iam-no-inline-policy-check (4 roles) | Each inline policy belongs to exactly one role and is managed by Terraform with that role. AWS guidance allows inline policies for a strict one-to-one relationship; a managed policy would also need `iam:CreatePolicy` for the pipeline, a wider right. |
| s3-bucket-versioning-enabled (3 buckets) | Versioning **is** enabled on all 3. The pack also asks for MFA Delete, which can only be turned on with root access keys. This lab never creates root keys (rule iam-root-access-key-check is compliant). |
| s3-bucket-logging-enabled (3 buckets) | Server access logs would need another bucket. Object access on the Terraform state is recorded by CloudTrail data events; API calls on all buckets by the trail. |

## Not counted

- 18 manual checks (`AWS_CONFIG_PROCESS_CHECK`): contact details, security questions, CIS alarms. The
  CIS alarms exist (terraform/security/alerts.tf) but the pack expects them to be confirmed by hand.
- No resource to evaluate: RDS, EBS volumes, NACL/security group rules on ports other than SSH.

Config was then switched off (`enable_config = false`) to stay inside the 5 USD budget; the fixes
stay in place. It can be switched on again for a new measurement.
