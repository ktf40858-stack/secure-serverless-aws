# Secure Serverless on AWS

A small serverless web app on AWS, built and secured end to end:
infrastructure as code, a keyless CI/CD pipeline, least-privilege IAM,
detection, automatic remediation and CIS compliance, then attacked on
purpose to prove the controls work.

> Status: **Week 1 in progress** (secured account, Terraform base, OIDC pipeline).
> This README only describes what has actually been built.

## Architecture (target)

- API Gateway -> Lambda (Python) -> DynamoDB
- Static front end on S3 + CloudFront
- Terraform with remote state (S3 + locking)
- GitHub Actions deploying through OIDC (no stored AWS keys), Checkov gate
- CloudTrail, CloudWatch, AWS Config (CIS AWS Foundations)
- EventBridge -> remediation Lambda -> SNS alert
- Attack simulation with Stratus Red Team

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
