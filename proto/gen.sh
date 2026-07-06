#!/usr/bin/env bash
# Regenerate per-language types from the shared protos.
# Requires: protoc (brew install protobuf) and protoc-gen-go
#   (go install google.golang.org/protobuf/cmd/protoc-gen-go@latest).
# Generated code is committed, so service builds don't need protoc. Re-run this
# whenever a .proto changes.
set -euo pipefail
cd "$(dirname "$0")/.." # repo root
export PATH="$PATH:$(go env GOPATH)/bin"

PROTO=proto/transcript.proto

# Go -> summarize-go (module option strips the prefix; go_package places it in gen/arpv1)
protoc --proto_path=proto \
  --go_out=services/summarize-go \
  --go_opt=module=github.com/anthonywittig/audio-recording-processor/services/summarize-go \
  "$PROTO"

# Java -> transcribe-java (java_package/java_multiple_files set in the proto)
protoc --proto_path=proto \
  --java_out=services/transcribe-java/src/main/java \
  "$PROTO"

# Python -> action-items-py
protoc --proto_path=proto \
  --python_out=services/action-items-py \
  "$PROTO"

echo "generated."
