#!/usr/bin/env bash
# Renders and applies the worker manifests.
#
# The manifests in workers/*.yaml.tmpl are templates so the AWS account ID (and
# region) are never committed. Values come from Terraform outputs — the single
# source of truth — or, if you don't want to hit Terraform, from a gitignored
# k8s/config.env (copy config.env.example). config.env wins over Terraform.
#
# Requires: envsubst (macOS: `brew install gettext`), kubectl, and — unless
# config.env is present — terraform with access to the poc state.
#
# Usage: ./k8s/apply.sh
set -euo pipefail

cd "$(dirname "$0")"
TF_DIR=../infra/terraform/poc

# 1) optional local override file (gitignored)
if [ -f config.env ]; then
  # shellcheck disable=SC1091
  set -a; . ./config.env; set +a
fi

# 2) fall back to Terraform outputs for anything not already set
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null || true; }
: "${AWS_ACCOUNT_ID:=$(tf_out account_id)}"
: "${AWS_REGION:=$(tf_out region)}"

if [ -z "${AWS_ACCOUNT_ID:-}" ] || [ -z "${AWS_REGION:-}" ]; then
  echo "error: AWS_ACCOUNT_ID / AWS_REGION are unset and could not be read from" >&2
  echo "       Terraform ($TF_DIR). Set them in k8s/config.env (see" >&2
  echo "       config.env.example) or run 'terraform apply' in the poc dir first." >&2
  exit 1
fi

export AWS_ACCOUNT_ID AWS_REGION
echo "rendering manifests with account=$AWS_ACCOUNT_ID region=$AWS_REGION"

# Namespace first — the Deployments below live in it. No templating needed.
kubectl apply -f workers/00-namespace.yaml

# Restrict substitution to our two vars so nothing else in the YAML is touched.
for tmpl in workers/*.yaml.tmpl; do
  echo "applying $tmpl"
  envsubst '${AWS_ACCOUNT_ID} ${AWS_REGION}' < "$tmpl" | kubectl apply -f -
done
