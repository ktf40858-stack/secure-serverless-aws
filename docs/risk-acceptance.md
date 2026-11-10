# Risk acceptance register

Checks that are deliberately not applied, with the reason. Every skip in the
code (`#checkov:skip=`) must have a line here.

| Check | Resource | Decision | Reason | Review |
|---|---|---|---|---|
| CKV_AWS_145 (KMS CMK) | Terraform state bucket | SSE-S3 (AES256) | A customer managed key costs about 1 USD/month, 20 % of the lab budget. State holds no secrets. | Before any production use |
| CKV_AWS_144 (cross-region replication) | Terraform state bucket | Not enabled | Versioning plus 90-day retention covers recovery. Replication doubles storage cost. | Before any production use |
| CKV_AWS_18 (access logging) | Terraform state bucket | Not enabled | Access is audited with CloudTrail S3 data events (week 3). | Week 3 |
| CKV2_AWS_62 (event notifications) | Terraform state bucket | Not enabled | No consumer for state change events. | n/a |
