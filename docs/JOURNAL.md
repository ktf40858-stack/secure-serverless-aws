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
- Notes API written (app/api/src/handler.py): strict input validation, no internal errors leaked,
  security headers, structured logs without note content. 17 unit tests with moto: all pass.
  Bug caught before running: DynamoDB returns Decimal, json.dumps would have crashed (500 on read).
- Dev environment Terraform: DynamoDB (PITR, encryption), Lambda (arm64, 128 MB, reserved concurrency 5,
  X-Ray), HTTP API (throttling 10/20, access logs), invoke permission scoped to this API.
- Deploy role permissions scoped to notes-dev*. Manual review found a privilege escalation path
  (pipeline could create an admin role and assume it) that Checkov did not flag: fixed with a
  permissions boundary (notes-dev-boundary) required on CreateRole/PutRolePolicy.
- GitHub Actions workflow: tests, fmt, validate, Checkov gate, OIDC plan, apply from main with approval.
- Checkov: Terraform 113/0 (18 documented skips), workflow 84/0. Threat model STRIDE written.
