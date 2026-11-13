# Identity for the notes API (threat model S1).
# Users are created by an admin only: no public sign-up, so nobody on the Internet can mint a token.

resource "aws_cognito_user_pool" "users" {
  name                = "${local.name}-users"
  deletion_protection = "INACTIVE" # lab: destroyed after each session
  username_attributes = ["email"]
  mfa_configuration   = "OPTIONAL"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 14
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 1
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  user_pool_add_ons {
    advanced_security_mode = "OFF" # paid feature (threat protection), out of the lab budget
  }
}

resource "aws_cognito_user_pool_client" "api" {
  name         = "${local.name}-api-client"
  user_pool_id = aws_cognito_user_pool.users.id

  generate_secret                      = false     # public client (CLI / SPA): a secret could not be kept
  prevent_user_existence_errors        = "ENABLED" # same answer for unknown user and bad password
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = false

  # USER_PASSWORD_AUTH lets the lab test the API from the CLI. A real front end would use SRP or the
  # hosted UI with PKCE instead (see docs/risk-acceptance.md).
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 1
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

# API Gateway checks the signature, issuer, expiry and audience of every token before Lambda runs.
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.notes.id
  name             = "${local.name}-cognito"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://${aws_cognito_user_pool.users.endpoint}"
    audience = [aws_cognito_user_pool_client.api.id]
  }
}
