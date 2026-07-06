# Phase 6 — SES inbound email intake.
#
# Email an audio attachment to the (unguessable) address in the `inbound_email_address`
# output; SES stores the raw MIME in the inbound bucket under raw/, the inbound-parser
# Lambda extracts the audio attachment and writes it to the ingest bucket's audio/
# prefix, and the existing Phase 5 path (S3 -> SQS -> intake-ts -> workflow) runs.
#
# witski.com's DNS is NOT in Route 53 in this account, so the MX and domain-verification
# records must be added by hand at the DNS provider (`terraform output inbound_dns_records`).
# Receiving stays inert until those propagate and SES marks the domain verified.

variable "inbound_domain" {
  description = "Subdomain that receives inbound audio email (gets its own MX -> SES)."
  type        = string
  default     = "inbound.witski.com"
}

# Unguessable local part. Any sender is allowed, so the address itself is the only
# gate — keep it in Terraform state (private) rather than in this public source tree.
resource "random_id" "inbound_local" {
  byte_length = 6
}

locals {
  inbound_address = "arp-${random_id.inbound_local.hex}@${var.inbound_domain}"
}

# --- SES domain identity for the receiving subdomain. No verification wait: the TXT
#     record is added out-of-band at the DNS provider, so blocking here would deadlock.
resource "aws_ses_domain_identity" "inbound" {
  domain = var.inbound_domain
}

# --- Raw inbound MIME bucket (separate from ingest so the audio/ notification the
#     Phase 5 intake relies on stays untouched). ---
resource "aws_s3_bucket" "inbound" {
  bucket        = "${local.name}-inbound-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # POC: allow destroy with objects present
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "inbound" {
  bucket                  = aws_s3_bucket.inbound.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Raw messages are throwaway once parsed; expire them to keep the bucket cheap.
resource "aws_s3_bucket_lifecycle_configuration" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  rule {
    id     = "expire-raw"
    status = "Enabled"
    filter {
      prefix = "raw/"
    }
    expiration {
      days = 7
    }
  }
}

# Let SES write incoming mail into the bucket (scoped to this account's receipt rules).
data "aws_iam_policy_document" "inbound_bucket" {
  statement {
    sid       = "AllowSESPuts"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.inbound.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:receipt-rule-set/${aws_ses_receipt_rule_set.main.rule_set_name}:receipt-rule/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  policy = data.aws_iam_policy_document.inbound_bucket.json
}

# --- Receipt rule set + rule. Only one rule set is active per account/region; nothing
#     else in this account uses SES receiving, so we own it. ---
resource "aws_ses_receipt_rule_set" "main" {
  rule_set_name = "${local.name}-inbound"
}

resource "aws_ses_active_receipt_rule_set" "main" {
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
}

resource "aws_ses_receipt_rule" "store" {
  name          = "store-audio"
  rule_set_name = aws_ses_receipt_rule_set.main.rule_set_name
  recipients    = [local.inbound_address]
  enabled       = true
  scan_enabled  = true # SES spam/virus scan
  tls_policy    = "Require"

  s3_action {
    bucket_name       = aws_s3_bucket.inbound.id
    object_key_prefix = "raw/"
    position          = 1
  }

  # SES validates it can write to the bucket when the rule is saved.
  depends_on = [aws_s3_bucket_policy.inbound]
}

# --- Lambda: parse raw MIME -> extract audio attachment -> ingest audio/. ---
data "archive_file" "inbound_parser" {
  type        = "zip"
  source_file = "${path.module}/../../../services/inbound-parser-py/handler.py"
  output_path = "${path.module}/.build/inbound-parser.zip"
}

data "aws_iam_policy_document" "inbound_lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "inbound_lambda" {
  name               = "${local.name}-inbound-parser"
  assume_role_policy = data.aws_iam_policy_document.inbound_lambda_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "inbound_lambda" {
  statement {
    sid       = "ReadRawMime"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.inbound.arn}/raw/*"]
  }
  statement {
    sid       = "WriteAudio"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.ingest.arn}/audio/*"]
  }
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "inbound_lambda" {
  name   = "${local.name}-inbound-parser"
  role   = aws_iam_role.inbound_lambda.id
  policy = data.aws_iam_policy_document.inbound_lambda.json
}

resource "aws_lambda_function" "inbound_parser" {
  function_name    = "${local.name}-inbound-parser"
  role             = aws_iam_role.inbound_lambda.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.inbound_parser.output_path
  source_code_hash = data.archive_file.inbound_parser.output_base64sha256
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      INGEST_BUCKET = aws_s3_bucket.ingest.id
      AUDIO_PREFIX  = "audio/"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "inbound_s3" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.inbound_parser.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.inbound.arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "inbound" {
  bucket = aws_s3_bucket.inbound.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.inbound_parser.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
  }
  depends_on = [aws_lambda_permission.inbound_s3]
}

# --- Outputs ---
output "inbound_email_address" {
  description = "Send audio attachments here. Kept out of public docs on purpose."
  value       = local.inbound_address
}

output "inbound_dns_records" {
  description = "Add these at the witski.com DNS provider to enable receiving."
  value = {
    verification_txt = {
      name  = "_amazonses.${var.inbound_domain}"
      type  = "TXT"
      value = aws_ses_domain_identity.inbound.verification_token
    }
    mx = {
      name  = var.inbound_domain
      type  = "MX"
      value = "10 inbound-smtp.${var.region}.amazonaws.com"
    }
  }
}
