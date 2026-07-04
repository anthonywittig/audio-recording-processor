# Phase 5 — automatic intake.
# An audio upload to s3://<ingest>/audio/ fires an S3 event to SQS; the in-cluster
# intake-ts service consumes it and starts the processAudio workflow.

resource "aws_sqs_queue" "intake" {
  name                       = "${local.name}-intake"
  visibility_timeout_seconds = 60   # must exceed the time to start a workflow
  message_retention_seconds  = 3600 # POC: drop unprocessed events after 1h
  tags                       = local.common_tags
}

# Allow the ingest bucket to publish notifications to the queue.
data "aws_iam_policy_document" "intake_queue_policy" {
  statement {
    sid     = "AllowS3SendMessage"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    resources = [aws_sqs_queue.intake.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.ingest.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "intake" {
  queue_url = aws_sqs_queue.intake.id
  policy    = data.aws_iam_policy_document.intake_queue_policy.json
}

resource "aws_s3_bucket_notification" "ingest" {
  bucket = aws_s3_bucket.ingest.id
  queue {
    queue_arn     = aws_sqs_queue.intake.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "audio/"
  }
  depends_on = [aws_sqs_queue_policy.intake]
}

# --- IRSA for the intake service: consume the queue (no S3 needed; the event
#     carries bucket/key, and starting the workflow is a Temporal call). ---

data "aws_iam_policy_document" "intake_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.app_namespace}:intake-ts"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "intake" {
  name               = "${local.name}-intake"
  assume_role_policy = data.aws_iam_policy_document.intake_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "intake" {
  statement {
    sid       = "IntakeQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.intake.arn]
  }
}

resource "aws_iam_role_policy" "intake" {
  name   = "${local.name}-intake"
  role   = aws_iam_role.intake.id
  policy = data.aws_iam_policy_document.intake.json
}

output "intake_queue_url" {
  value = aws_sqs_queue.intake.id
}

output "intake_role_arn" {
  value = aws_iam_role.intake.arn
}
