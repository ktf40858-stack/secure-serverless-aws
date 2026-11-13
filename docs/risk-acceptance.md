# Risk acceptance register

Checks that are deliberately not applied, with the reason. Every skip in the
code (`#checkov:skip=`) must have a line here.

| Check | Resource | Decision | Reason | Review |
|---|---|---|---|---|
| CKV_AWS_145 (KMS CMK) | Terraform state bucket | SSE-S3 (AES256) | A customer managed key costs about 1 USD/month, 20 % of the lab budget. State holds no secrets. | Before any production use |
| CKV_AWS_144 (cross-region replication) | Terraform state bucket | Not enabled | Versioning plus 90-day retention covers recovery. Replication doubles storage cost. | Before any production use |
| CKV_AWS_18 (access logging) | Terraform state bucket | Not enabled | Access is audited with CloudTrail S3 data events (built 2026-11-12). | Done |
| CKV2_AWS_62 (event notifications) | Terraform state bucket | Not enabled | No consumer for state change events. | n/a |
| CKV_AWS_119 (KMS CMK) | DynamoDB notes table | AWS owned key | Same budget reason; data is demo notes. | Before any production use |
| CKV_AWS_158 (KMS CMK) | Lambda and API log groups | AWS managed encryption | Same budget reason. | Before any production use |
| CKV_AWS_338 (1 year retention) | Lambda and API log groups | 30 days | Lab only; keeps storage cost near zero. | Before any production use |
| CKV_AWS_117 (Lambda in VPC) | notes-dev-api | No VPC | The function only calls DynamoDB; a VPC would need a NAT gateway (about 32 USD/month) or VPC endpoints. | Before any production use |
| CKV_AWS_116 (DLQ) | notes-dev-api | No DLQ | Synchronous invocations: errors return to the caller, a DLQ would never receive anything. | n/a |
| CKV_AWS_272 (code signing) | notes-dev-api | Not enabled | The pipeline is the only deploy path; signing is a planned improvement. | Week 4 |
| CKV_AWS_173 (env var encryption with CMK) | notes-dev-api | AWS managed | Environment holds only the table name, no secret. | n/a |
| ~~CKV_AWS_309 (route authorization)~~ | 4 API routes | **Closed 2026-11-12** | Cognito JWT authorizer on every route; skip removed. | Done |
| Lambda reserved concurrency | notes-dev-api | -1 (none) | New accounts have a total quota of 10 and AWS refuses a reservation that leaves fewer than 10 unreserved. Cap = account quota + API throttling. | When the quota is raised |
| Cognito USER_PASSWORD_AUTH | notes-dev-api-client | Enabled | Lets the lab get tokens from the CLI. The password goes to Cognito over TLS only, never to the API. A real front end would use SRP or the hosted UI with PKCE. | Before any front end |
| Cognito threat protection | notes-dev-users | Off | Paid feature (per active user). Mitigated: admin-only sign-up, 14-char password policy, user existence errors hidden, 60-min tokens, revocation enabled. | Before any production use |
| CKV_AWS_111 (write without constraints) | Permissions boundary, X-Ray statement | `*` | X-Ray has no resource-level permissions. | n/a |
| CKV_AWS_35 (KMS for CloudTrail) | secbaseline-trail | SSE-S3 | Budget (CMK 1 USD/month). Integrity covered by log file validation. | Before any production use |
| CKV_AWS_252 (SNS per log file) | secbaseline-trail | Not enabled | Alerts come from metric filters and EventBridge, not per file. | n/a |
| CKV_AWS_26 (SNS encryption) | secbaseline-security-alerts | Not encrypted | CloudWatch alarms cannot publish to a topic using the AWS managed SNS key; a CMK costs 1 USD/month. Alerts hold no secrets. | Before any production use |
| CKV_AWS_18 / 144 / 145 / CKV2_AWS_62 | CloudTrail bucket | Same as the state bucket | Same budget reasons; the bucket is locked to CloudTrail of this trail and TLS only. | Before any production use |
| Alarm threshold | unauthorized-api-calls | 5 in 5 min (CIS says 1) | Terraform refresh produces occasional expected AccessDenied; 5 keeps the alert meaningful. | Revisit after 1 month of data |
| CIS iam-no-inline-policy-check | 4 roles | Inline policies | One policy per role, managed with the role; managed policies would need iam:CreatePolicy in the pipeline. See docs/cis-score.md. | n/a |
| CIS s3-bucket-versioning-enabled (MFA Delete) | 3 buckets | Versioning on, MFA Delete off | MFA Delete requires root access keys, which this account never creates. | n/a |
| CIS s3-bucket-logging-enabled | 3 buckets | No server access logs | CloudTrail data events on the state bucket, management events on all buckets. | Before any production use |
