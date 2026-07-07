# API: HTTP API Gateway -> single Node Lambda (services/web-api-ts). Reached
# only through CloudFront's /api/* behavior in practice, though the execute-api
# endpoint is also public (the Lambda checks the passcode either way).
#
# Build the Lambda bundle BEFORE apply: ./services/web-api-ts/build.sh

data "archive_file" "web_api" {
  type        = "zip"
  source_file = "${path.module}/../../../services/web-api-ts/dist/index.mjs"
  output_path = "${path.module}/.build/web-api.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "web_api" {
  name               = "${local.name}-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "web_api_logs" {
  role       = aws_iam_role.web_api.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "web_api" {
  statement {
    sid       = "IngestObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::${local.ingest_bucket}/*"]
  }
  statement {
    sid       = "IngestList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.ingest_bucket}"]
  }
  statement {
    sid       = "PasscodeSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.web_passcode.arn]
  }
}

resource "aws_iam_role_policy" "web_api" {
  name   = "${local.name}-api"
  role   = aws_iam_role.web_api.id
  policy = data.aws_iam_policy_document.web_api.json
}

resource "aws_lambda_function" "web_api" {
  function_name    = "${local.name}-api"
  role             = aws_iam_role.web_api.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  filename         = data.archive_file.web_api.output_path
  source_code_hash = data.archive_file.web_api.output_base64sha256
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      INGEST_BUCKET      = local.ingest_bucket
      PASSCODE_SECRET_ID = aws_secretsmanager_secret.web_passcode.name
    }
  }
}

resource "aws_cloudwatch_log_group" "web_api" {
  name              = "/aws/lambda/${aws_lambda_function.web_api.function_name}"
  retention_in_days = 14
}

resource "aws_apigatewayv2_api" "web" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.web.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "web_api" {
  api_id                 = aws_apigatewayv2_api.web.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.web_api.invoke_arn
  payload_format_version = "2.0"
}

# Explicit routes (not a catch-all) so anything unexpected 404s at the gateway.
resource "aws_apigatewayv2_route" "list_recordings" {
  api_id    = aws_apigatewayv2_api.web.id
  route_key = "GET /api/recordings"
  target    = "integrations/${aws_apigatewayv2_integration.web_api.id}"
}

resource "aws_apigatewayv2_route" "create_upload" {
  api_id    = aws_apigatewayv2_api.web.id
  route_key = "POST /api/recordings"
  target    = "integrations/${aws_apigatewayv2_integration.web_api.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.web_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.web.execution_arn}/*/*"
}
