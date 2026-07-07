#!/usr/bin/env bash
# Bundle the Lambda into dist/index.mjs. Run this before `terraform apply` in
# infra/terraform/web (the archive_file data source zips dist/).
#
# The AWS SDK v3 is provided by the nodejs22.x runtime, so it stays external —
# the bundle is just our handler.
set -euo pipefail
cd "$(dirname "$0")"

npm ci
npx esbuild src/index.ts \
  --bundle \
  --platform=node \
  --target=node22 \
  --format=esm \
  --external:@aws-sdk/* \
  --outfile=dist/index.mjs

echo "built dist/index.mjs"
