# One ECR repository per container image we build (see var.ecr_repositories).
# Images are pushed by each service's build script; the k8s Deployments pull
# from here. force_delete lets `terraform destroy` remove repos with images.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.ecr_repositories)

  name                 = "${local.name}/${each.value}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false # keep POC costs/noise down
  }

  tags = local.common_tags
}

# Expire untagged images after a day so old layers don't accumulate cost.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 1 day"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 1
      }
      action = { type = "expire" }
    }]
  })
}
