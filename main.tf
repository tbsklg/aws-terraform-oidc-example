provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      hashicorp-learn = "lambda-api-gateway"
    }
  }
}

resource "random_pet" "lambda_bucket_name" {
  prefix = "hello-world"
  length = 4
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket_name.id
}

resource "aws_s3_bucket" "lambda_get_settings_bucket" {
  bucket = "${random_pet.lambda_bucket_name.id}-get-settings"
}

resource "aws_s3_bucket" "lambda_put_settings_bucket" {
  bucket = "${random_pet.lambda_bucket_name.id}-put-settings"
}

data "archive_file" "lambda_hello_world" {
  type = "zip"

  source_dir  = "${path.module}/hello-world"
  output_path = "${path.module}/hello-world.zip"
}

data "archive_file" "lambda_get_settings" {
  type = "zip"

  source_dir  = "${path.module}/get-settings"
  output_path = "${path.module}/get-settings.zip"
}

data "archive_file" "lambda_put_settings" {
  type = "zip"

  source_dir  = "${path.module}/put-settings"
  output_path = "${path.module}/put-settings.zip"
}

resource "aws_s3_object" "lambda_get_settings" {
  bucket = aws_s3_bucket.lambda_get_settings_bucket.id

  key    = "get-settings.zip"
  source = data.archive_file.lambda_get_settings.output_path

  etag = filemd5(data.archive_file.lambda_get_settings.output_path)
}

resource "aws_s3_object" "lambda_put_settings" {
  bucket = aws_s3_bucket.lambda_put_settings_bucket.id

  key    = "put-settings.zip"
  source = data.archive_file.lambda_put_settings.output_path

  etag = filemd5(data.archive_file.lambda_put_settings.output_path)
}

resource "aws_s3_object" "lambda_hello_world" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "hello-world.zip"
  source = data.archive_file.lambda_hello_world.output_path

  etag = filemd5(data.archive_file.lambda_hello_world.output_path)
}

resource "aws_lambda_function" "hello_world" {
  function_name = "HelloWorld"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_hello_world.key

  runtime = "nodejs16.x"
  handler = "hello.handler"

  source_code_hash = data.archive_file.lambda_hello_world.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "put_settings" {
  function_name = "PutSettings"

  s3_bucket = aws_s3_bucket.lambda_put_settings_bucket.id
  s3_key    = aws_s3_object.lambda_put_settings.key

  runtime = "nodejs16.x"
  handler = "putSettings.handler"

  source_code_hash = data.archive_file.lambda_put_settings.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "get_settings" {
  function_name = "GetSettings"

  s3_bucket = aws_s3_bucket.lambda_get_settings_bucket.id
  s3_key    = aws_s3_object.lambda_get_settings.key

  runtime = "nodejs16.x"
  handler = "getSettings.handler"

  source_code_hash = data.archive_file.lambda_get_settings.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

resource "aws_cloudwatch_log_group" "hello_world" {
  name = "/aws/lambda/${aws_lambda_function.hello_world.function_name}"

  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "put_settings" {
  name = "/aws/lambda/${aws_lambda_function.put_settings.function_name}"

  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "get_settings" {
  name = "/aws/lambda/${aws_lambda_function.get_settings.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "serverless_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "hello_world" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.hello_world.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "get_settings" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.get_settings.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "put_settings" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.put_settings.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_authorizer" "jwt_authorizer" {
  api_id          = aws_apigatewayv2_api.lambda.id
  authorizer_type = "JWT"
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.userpool_client.id]
    issuer   = "https://cognito-idp.eu-central-1.amazonaws.com/${aws_cognito_user_pool.userpool.id}"
  }
  identity_sources = ["$request.header.Authorization"]
  name             = "jwt-authorizer"
}

resource "aws_apigatewayv2_route" "hello_world" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key          = "GET /hello"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt_authorizer.id
  target             = "integrations/${aws_apigatewayv2_integration.hello_world.id}"
}

resource "aws_apigatewayv2_route" "get_settings" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key          = "GET /settings"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt_authorizer.id
  target             = "integrations/${aws_apigatewayv2_integration.get_settings.id}"
}

resource "aws_apigatewayv2_route" "put_settings" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key          = "PUT /settings"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt_authorizer.id
  target             = "integrations/${aws_apigatewayv2_integration.put_settings.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gw_get_settings" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_settings.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gw_put_settings" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.put_settings.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

resource "aws_iam_policy" "dynamo_db_lambda_policy" {
  name = "DynamoDBLambdaPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:*"
        ]
        Resource = [
          aws_dynamodb_table.user_settings.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda-policy-attachment" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.dynamo_db_lambda_policy.arn
}

resource "aws_cognito_user_pool_client" "userpool_client" {
  name                  = "client"
  user_pool_id          = aws_cognito_user_pool.userpool.id
  callback_urls         = ["https://example.com"]
  access_token_validity = 60
  id_token_validity     = 60
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
  explicit_auth_flows                  = ["ALLOW_CUSTOM_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid"]
  supported_identity_providers         = ["COGNITO"]
}

resource "random_pet" "cognito_user_pool_domain" {
  prefix = "userpool-domain"
  length = 4
}

resource "aws_cognito_user_pool_domain" "userpool_domain" {
  domain       = random_pet.cognito_user_pool_domain.id
  user_pool_id = aws_cognito_user_pool.userpool.id
}

resource "aws_cognito_user_pool" "userpool" {
  name = "userpool"
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_dynamodb_table" "user_settings" {
  name         = "user_settings"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"
  attribute {
    name = "UserId"
    type = "S"
  }
}
