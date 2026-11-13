output "api_url" {
  description = "Base URL of the notes API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "table_name" {
  value = aws_dynamodb_table.notes.name
}

output "lambda_name" {
  value = aws_lambda_function.api.function_name
}

output "user_pool_id" {
  value = aws_cognito_user_pool.users.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.api.id
}
