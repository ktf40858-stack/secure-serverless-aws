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

## 2026-11-10 - Account secured, bootstrap deployed

- AWS account created (Free plan). Root: MFA (virtual authenticator), no access keys.
- IAM Identity Center deliberately NOT enabled: it creates an AWS Organization, which moves the
  account to the paid plan and drops the free-plan credits. Instead: IAM user `kodjo-admin` in an
  `admins` group (AdministratorAccess), console access with MFA, no access keys.
- CLI access with `aws login` (short-lived credentials from the console session, auto-refreshed),
  profile `lab`. No long-term keys on the laptop.
- `terraform apply` of the bootstrap: 13 resources created (budget 5 USD/month with 80% actual and
  100% forecast alerts, state bucket, GitHub OIDC provider, deploy role, permissions boundary).
  Checked with the CLI: public access block all true, versioning Enabled, budget 5.0 MONTHLY.
- Bootstrap state is local (terraform/bootstrap/terraform.tfstate, git-ignored): keep a backup.

## 2026-11-12 - Dev environment deployed

- Bootstrap state backed up outside the repo. `backend.hcl` (git-ignored) points the dev env to the
  remote S3 state bucket with native locking.
- Pre-apply check found a blocker: new accounts have a Lambda concurrency quota of 10, and AWS refuses
  any reservation that leaves fewer than 10 unreserved, so `reserved_concurrent_executions = 5` would
  have failed. Set to -1 (documented in variables.tf); the cap comes from the account quota (10) and
  API Gateway throttling (10 rps, burst 20). To restore to 5 once the quota is raised.
- `terraform apply` dev: 14 resources (HTTP API, 4 routes, Lambda, DynamoDB, IAM role, 2 log groups).
  Checkov dev: 44 passed, 0 failed.
- Live tests against the deployed API: POST 201, list 200, get 200, delete 204, get after delete 404,
  unexpected field rejected 400, unknown route 404. Security headers present (HSTS, nosniff,
  no-store). Lambda logs are structured JSON with no note content.
- Review of the pipeline before enabling it found a second blocker: the apply job runs in the GitHub
  environment "dev", so its OIDC `sub` claim is `repo:...:environment:dev`, not the branch. The trust
  policy only allowed `ref:refs/heads/main`, so the apply job would have been denied. Fixed: trust now
  lists exactly the two contexts (main branch, dev environment); pull_request tokens stay untrusted and
  the plan job now runs only on push to main.
- First pipeline run with AWS enabled: the plan job was denied (`Not authorized to perform
  sts:AssumeRoleWithWebIdentity`). CloudTrail showed the real `sub` claim: this repository uses
  GitHub's immutable subject format `repo:owner@owner_id/name@repo_id:...`, not `repo:owner/name:...`.
  Trust policy updated to the immutable form (variable `github_oidc_subject_repo`); this is also
  stronger, since a renamed or recreated repo with the same name cannot reuse the trust.
- Re-run: tests and Checkov gate green, plan via OIDC green, apply from main green. No long-term AWS
  keys anywhere in GitHub. The CI plan showed one in-place Lambda change: the zip built on Linux has
  a different hash from the one built on Windows (file metadata), the code itself is the same.
  API checked again after the CI apply: 200.

## 2026-11-12 - Week 3, part 1: authentication, ownership, supply chain

- Cognito user pool: admin-only sign-up, 14-char password policy, optional TOTP MFA, user existence
  errors hidden, 60-minute tokens, revocation enabled. JWT authorizer on all 4 routes.
- Ownership: table key changed to (owner = Cognito sub, id). Get/Delete use both, list is a Query on
  the caller's partition, Scan removed from the Lambda role. The handler also refuses any request
  without a valid `sub` (defence in depth) and never returns the owner. Unit tests: 24 pass.
- Deploy role: Cognito permissions scoped by tags (ABAC) because pool ARNs contain a random id.
- All GitHub Actions pinned to full commit SHAs (latest majors, Node 24), Dependabot added.
- First CI deploy failed on `logs:CreateLogDelivery` (needed to update stage access logs, no
  resource-level permissions). Least privilege worked as intended: added exactly the log-delivery
  actions, re-ran, green. The whole week 3 change was deployed by the pipeline, not from the laptop.
- Live test with two test users (scripts/smoke_test_auth.sh): no token 401, forged token 401, wrong
  password and unknown user give the same error, Bob cannot read or delete Alice's note (404, note
  untouched), Alice can. 7/7 PASS.
