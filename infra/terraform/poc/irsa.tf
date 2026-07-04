# IRSA (IAM Roles for Service Accounts) grants each worker pod least-privilege
# AWS access via the cluster's OIDC provider. A pod using ServiceAccount
# `<ns>:<name>` can assume the role whose trust policy matches that subject.
#
# This file currently defines the role for the summarize (Go) worker. Roles for
# the other workers follow the same pattern and will be added as they deploy.

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
