# IRSA (IAM Roles for Service Accounts) grants each worker pod least-privilege
# AWS access via the cluster's OIDC provider. A pod using ServiceAccount
# `<ns>:<name>` can assume the role whose trust policy matches that subject.
#
# One role per activity worker: summarize (Go), transcribe (Java), action-items
# (Python). The intake service's role lives in intake.tf.

# --- summarize (Go): read OpenAI key from Secrets Manager + S3 read/write ---

data "aws_iam_policy_document" "summarize_assume" {
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
      values   = ["system:serviceaccount:${local.app_namespace}:summarize-go"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "summarize" {
  name               = "${local.name}-summarize"
  assume_role_policy = data.aws_iam_policy_document.summarize_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "summarize" {
  statement {
    sid       = "OpenAISecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.openai.arn]
  }
  statement {
    sid       = "IngestObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.ingest.arn}/*"]
  }
  statement {
    sid       = "IngestList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ingest.arn]
  }
}

resource "aws_iam_role_policy" "summarize" {
  name   = "${local.name}-summarize"
  role   = aws_iam_role.summarize.id
  policy = data.aws_iam_policy_document.summarize.json
}

output "summarize_role_arn" {
  description = "IRSA role ARN for the summarize-go ServiceAccount."
  value       = aws_iam_role.summarize.arn
}

# --- transcribe (Java): AWS Transcribe + S3 read/write ---

data "aws_iam_policy_document" "transcribe_assume" {
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
      values   = ["system:serviceaccount:${local.app_namespace}:transcribe-java"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "transcribe" {
  name               = "${local.name}-transcribe"
  assume_role_policy = data.aws_iam_policy_document.transcribe_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "transcribe" {
  statement {
    sid       = "Transcribe"
    actions   = ["transcribe:StartTranscriptionJob", "transcribe:GetTranscriptionJob"]
    resources = ["*"]
  }
  statement {
    sid       = "IngestObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.ingest.arn}/*"]
  }
  statement {
    sid       = "IngestList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ingest.arn]
  }
}

resource "aws_iam_role_policy" "transcribe" {
  name   = "${local.name}-transcribe"
  role   = aws_iam_role.transcribe.id
  policy = data.aws_iam_policy_document.transcribe.json
}

output "transcribe_role_arn" {
  value = aws_iam_role.transcribe.arn
}

# --- action-items (Python): OpenAI key from Secrets Manager + S3 read/write ---

data "aws_iam_policy_document" "action_items_assume" {
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
      values   = ["system:serviceaccount:${local.app_namespace}:action-items-py"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "action_items" {
  name               = "${local.name}-action-items"
  assume_role_policy = data.aws_iam_policy_document.action_items_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "action_items" {
  statement {
    sid       = "OpenAISecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.openai.arn]
  }
  statement {
    sid       = "IngestObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.ingest.arn}/*"]
  }
  statement {
    sid       = "IngestList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ingest.arn]
  }
}

resource "aws_iam_role_policy" "action_items" {
  name   = "${local.name}-action-items"
  role   = aws_iam_role.action_items.id
  policy = data.aws_iam_policy_document.action_items.json
}

output "action_items_role_arn" {
  value = aws_iam_role.action_items.arn
}
