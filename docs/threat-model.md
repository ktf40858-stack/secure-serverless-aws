# Threat model (STRIDE)

Scope: the notes API (API Gateway HTTP API -> Lambda -> DynamoDB) and the
GitHub Actions deploy pipeline. Status column shows what is **built today**,
not what is planned.

## Data flow

```mermaid
flowchart LR
  user([Internet client]) -->|password, TLS| cog[Cognito user pool<br/>admin-only sign-up]
  cog -->|JWT 60 min| user
  user -->|HTTPS + Bearer JWT| apigw[API Gateway HTTP API<br/>JWT authorizer, throttling, access logs]
  apigw -->|invoke, source ARN scoped| fn[Lambda notes-dev-api<br/>least-privilege role + boundary]
  fn -->|Get/Put/Delete/Query, key = owner + id| ddb[(DynamoDB notes-dev<br/>encrypted, PITR)]
  fn --> logs[CloudWatch Logs]
  gh[GitHub Actions<br/>actions pinned by SHA] -->|OIDC, main / dev env only| role[Deploy role<br/>scoped to notes-dev* + tags]
  role --> tf[(S3 state bucket<br/>versioned, TLS only)]
  role -->|terraform apply| apigw
```

Trust boundaries: Internet / AWS edge, API Gateway / Lambda, Lambda / data,
GitHub / AWS account.

## Threats and controls

| ID | STRIDE | Threat | Control | Status |
|---|---|---|---|---|
| S1 | Spoofing | Anyone can call the API (no authentication) | Cognito JWT authorizer on all 4 routes (signature, issuer, audience, expiry checked by API Gateway); admin-only sign-up; handler refuses a request without a valid `sub` (defence in depth) | Built 2026-11-12, tested live |
| S4 | Spoofing / Info disclosure | Authenticated user reads or deletes another user's note by guessing or knowing its id (IDOR) | Table key is (owner = Cognito `sub`, id); every Get/Delete uses both; list is a Query on the caller's partition, Scan removed from the role; another user's note returns the same 404 as a missing one; owner never returned | Built 2026-11-12, unit tests + live test with 2 users |
| S2 | Spoofing | Stolen long-lived AWS keys used to deploy | No keys at all: GitHub OIDC, role trusted only for this repo's immutable subject (`owner@id/repo@id`) from `main` or the `dev` environment; pull requests not trusted | Built |
| S3 | Spoofing | Another AWS service or account invokes the Lambda | `aws_lambda_permission` scoped to this API's execution ARN and `/notes*` routes | Built |
| T1 | Tampering | Malformed or oversized input reaches the database | Strict validation: JSON object only, allowed keys, types, lengths, 4 KB cap, no base64 | Built, 17 unit tests |
| T2 | Tampering | Path traversal or injection through the note id | id must match `^[0-9a-f]{32}$` before any call | Built, tested |
| T3 | Tampering | Terraform state edited or deleted | Versioned bucket, TLS-only policy, public access blocked, 90-day version history | Built |
| T4 | Tampering | Insecure infrastructure merged into main | Checkov gate fails the build; apply only from main with manual approval (`dev` environment) | Built |
| R1 | Repudiation | No trace of who called what | API Gateway access logs (request id, IP, route, status) + structured Lambda logs | Built |
| R2 | Repudiation | No trace of AWS API activity | CloudTrail | Week 3 |
| I1 | Information disclosure | Stack traces or AWS details returned to the caller | Catch-all handler returns `{"error":"internal error"}`, tested | Built |
| I2 | Information disclosure | Data readable at rest | DynamoDB and S3 encryption (AWS managed keys, KMS CMK out of budget) | Built, risk accepted |
| I3 | Information disclosure | Note content in logs | Logs record action, status, request id and IP, never the note | Built |
| D1 | Denial of service | Request flood | API throttling (10 rps, burst 20) | Built |
| D2 | Denial of wallet | Flood turns into a large bill | Account Lambda quota (10 concurrent), API throttling, authentication required, on-demand DynamoDB, 5 USD budget alert | Built (reserved concurrency not possible on a new account, see risk register) |
| E1 | Elevation of privilege | Lambda role abused to reach other data | Role limited to its log group and the notes table; trust limited to this account | Built |
| E2 | Elevation of privilege | Pipeline creates an admin role and assumes it | Deploy role can create or edit `notes-dev*` roles **only** with the `notes-dev-boundary` permissions boundary; PassRole only to Lambda | Built |
| E3 | Elevation of privilege | Compromised third-party GitHub Action | Every action pinned to a full commit SHA; Dependabot proposes updates | Built 2026-11-12 |
| E4 | Elevation of privilege | Pipeline touches identity resources it does not own | Cognito permissions scoped by tags (ABAC): create only with `Project`/`Environment=dev` tags, manage only pools carrying them | Built 2026-11-12 |

## Review log

- 2026-11-09: first version. E2 found by manual review: Checkov passed while the
  deploy role could still create an unbounded role. Fixed with a permissions boundary.
- 2026-11-12: S1, S4 (IDOR), E3 and E4 built. S2 updated to GitHub's immutable OIDC subject
  after a real AccessDenied seen in CloudTrail.
