#!/usr/bin/env bash
# Foolproof `terraform init` for the partial-backend stacks (poc, web).
#
# Both stacks leave the state-bucket name out of backend.tf (Terraform backend
# blocks can't use variables), so a bare `terraform init` would drop into an
# interactive bucket prompt. This wrapper always passes -backend-config from the
# shared backend.hcl and fails loudly if it's missing. Runnable from any cwd.
#
# Usage:
#   ./init.sh poc                 # or: ./init.sh web
#   ./init.sh poc -reconfigure    # extra args pass through to `terraform init`
set -euo pipefail

# Absolute dir of this script (= infra/terraform), so paths don't depend on cwd
# or on terraform's -chdir (which resolves -backend-config relative to the stack).
here="$(cd "$(dirname "$0")" && pwd)"

stack="${1:-}"
case "$stack" in
  poc | web) ;;
  *)
    echo "usage: $0 <poc|web> [extra terraform init args]" >&2
    exit 2
    ;;
esac

if [ ! -f "$here/backend.hcl" ]; then
  echo "error: backend.hcl not found in $here." >&2
  echo "       Copy the template and set your remote-state bucket:" >&2
  echo "         cp $here/backend.hcl.example $here/backend.hcl" >&2
  exit 1
fi

exec terraform -chdir="$here/$stack" init -backend-config="$here/backend.hcl" "${@:2}"
