# Secure Serverless on AWS

A small serverless web app on AWS, built and secured end to end:
infrastructure as code, a keyless CI/CD pipeline, least-privilege IAM,
detection, automatic remediation and CIS compliance, then attacked on
purpose to prove the controls work.

> Status: **code for weeks 1 and 2 written and checked locally, not deployed yet** (waiting for the AWS account).
> This README only describes what has actually been built.

## Architecture (target)

- API Gateway -> Lambda (Python) -> DynamoDB
- Static front end on S3 + CloudFront
- Terraform with remote state (S3 + locking)
- GitHub Actions deploying through OIDC (no stored AWS keys), Checkov gate
- CloudTrail, CloudWatch, AWS Config (CIS AWS Foundations)
- EventBridge -> remediation Lambda -> SNS alert
- Attack simulation with Stratus Red Team

## Security checks today (local)

| Check | Result |
|---|---|
| Unit tests (input validation, error handling, headers) | 17 passed |
| `terraform validate` (bootstrap + dev) | OK |
| Checkov, Terraform | 113 passed, 0 failed, 18 skipped with written reasons ([register](docs/risk-acceptance.md)) |
| Checkov, GitHub Actions workflow | 84 passed, 0 failed |
| Manual review | 1 privilege escalation found that Checkov missed, fixed with a permissions boundary ([threat model](docs/threat-model.md), E2) |

## Repository layout

| Folder | Content |
|---|---|
| `terraform/bootstrap` | One-time setup: state bucket, budget alert, GitHub OIDC role |
| `terraform/envs/dev` | The dev environment |
| `terraform/modules` | Reusable modules |
| `app/` | Lambda API and static front end |
| `remediation/` | Auto-remediation Lambdas |
| `attacks/` | Stratus Red Team scenarios and results |
| `docs/` | Diagrams, STRIDE threat model, runbooks, evidence |

## Progress

- [ ] Week 1: account hardening, budget alert, Terraform bootstrap, OIDC pipeline
- [ ] Week 2: application, IAM least privilege, Checkov in CI
- [ ] Week 3: logging, alerting, auto-remediation, AWS Config CIS
- [ ] Week 4: Stratus Red Team, attack -> detection -> remediation table, write-up

## Cost control

AWS Budgets alert at 5 USD, no NAT Gateway, no always-on EC2,
`terraform destroy` after each working session.
