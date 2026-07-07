#!/usr/bin/env bash
# Build the SPA and deploy it to the persistent web stack: sync to the site
# bucket, then invalidate CloudFront. Reads the targets from terraform outputs,
# so infra/terraform/web must be applied (and initialized) first.
set -euo pipefail
cd "$(dirname "$0")"

TF_DIR=../../infra/terraform/web

npm ci
npm run build

bucket=$(terraform -chdir="$TF_DIR" output -raw site_bucket)
dist_id=$(terraform -chdir="$TF_DIR" output -raw distribution_id)

aws s3 sync dist "s3://$bucket" --delete
aws cloudfront create-invalidation --distribution-id "$dist_id" --paths '/*' >/dev/null

echo "deployed: $(terraform -chdir="$TF_DIR" output -raw web_url)"
