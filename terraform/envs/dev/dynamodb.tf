resource "aws_dynamodb_table" "notes" {
  #checkov:skip=CKV_AWS_119:AWS owned key instead of a customer KMS key (1 USD/month, 20 % of the lab budget); see docs/risk-acceptance.md
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"
  # Partitioned by owner (Cognito sub): a user can only ever address their own items.
  hash_key  = "owner"
  range_key = "id"

  attribute {
    name = "owner"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = false # lab: destroyed after each session
}
