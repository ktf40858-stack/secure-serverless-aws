# Lab journal

Dated log of what was really done, used for the README, the CV and interviews.

## 2026-11-09
- Project folder created, tools installation started (AWS CLI, Terraform, Checkov).
- Tools installed: AWS CLI 2.39.5, Terraform 1.17.0, Checkov (in .venv).
- Terraform bootstrap written: 5 USD budget alert (80 % actual, 100 % forecast), state bucket
  (versioning, AES256, public access block, TLS-only policy, 90-day lifecycle, S3 native locking),
  GitHub OIDC provider and deploy role limited to the main branch of this repo.
- `terraform validate`: OK. Checkov: 44 passed, 0 failed, 4 skipped with written reasons
  (docs/risk-acceptance.md). First scan was 42 passed / 5 failed before fixes.
- Not deployed yet: waiting for the AWS account.
