resource "aws_apigatewayv2_api" "notes" {
  name          = "${local.name}-http"
  protocol_type = "HTTP"
}

resource "aws_cloudwatch_log_group" "api_access" {
  #checkov:skip=CKV_AWS_158:AWS managed encryption for log groups; a customer KMS key is out of the lab budget
  #checkov:skip=CKV_AWS_338:30 days of retention is enough for a lab and keeps cost near zero
  name              = "/aws/apigateway/${local.name}-http"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.notes.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.api_rate_limit
    throttling_burst_limit = var.api_burst_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId = "$context.requestId"
      sourceIp  = "$context.identity.sourceIp"
      time      = "$context.requestTime"
      method    = "$context.httpMethod"
      route     = "$context.routeKey"
      status    = "$context.status"
      latency   = "$context.responseLatency"
      userAgent = "$context.identity.userAgent"
    })
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.notes.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 6000
}

locals {
  routes = ["GET /notes", "POST /notes", "GET /notes/{id}", "DELETE /notes/{id}"]
}

resource "aws_apigatewayv2_route" "notes" {
  #checkov:skip=CKV_AWS_309:Public demo API in week 2; a Cognito JWT authorizer is planned (see docs/threat-model.md, S1)
  for_each  = toset(local.routes)
  api_id    = aws_apigatewayv2_api.notes.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Only this API (any stage, only the declared routes) may invoke the function.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.notes.execution_arn}/*/*/notes*"
}
