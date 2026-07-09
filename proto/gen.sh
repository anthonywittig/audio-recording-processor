#!/usr/bin/env bash
# Regenerate per-language types from the shared protos.
# Requires: protoc (brew install protobuf) and protoc-gen-go
#   (go install google.golang.org/protobuf/cmd/protoc-gen-go@latest).
# Generated code is committed, so service builds don't need protoc. Re-run this
# whenever a .proto changes.
#
# Each artifact is generated only for the languages that read or write it:
#   transcript    Java (write) + Go, Python, Ruby (read)
#   summary       Go (write)   + Ruby (read)
#   action_items  Python (write) + Ruby (read)
#   bundle        Ruby (write) + web app (read)
# The web app gets ts-proto interfaces ONLY (onlyTypes=true) — the proto-JSON is
# parsed with plain JSON.parse, so no proto runtime ships in the browser bundle.
set -euo pipefail
cd "$(dirname "$0")/.." # repo root
export PATH="$PATH:$(go env GOPATH)/bin"

GO_OUT="services/summarize-go"
GO_MOD="github.com/anthonywittig/audio-recording-processor/services/summarize-go"
JAVA_OUT="services/transcribe-java/src/main/java"
PY_OUT="services/action-items-py"
RUBY_OUT="services/bundle-ruby"
WEB_OUT="services/web-app/src/proto"

go_gen()   { protoc --proto_path=proto --go_out="$GO_OUT" --go_opt=module="$GO_MOD" "proto/$1"; }
java_gen() { protoc --proto_path=proto --java_out="$JAVA_OUT" "proto/$1"; }
py_gen()   { protoc --proto_path=proto --python_out="$PY_OUT" "proto/$1"; }
ruby_gen() { protoc --proto_path=proto --ruby_out="$RUBY_OUT" "proto/$1"; }
web_gen()  {
  mkdir -p "$WEB_OUT"
  protoc --proto_path=proto \
    --plugin=protoc-gen-ts_proto=services/web-app/node_modules/.bin/protoc-gen-ts_proto \
    --ts_proto_out="$WEB_OUT" \
    --ts_proto_opt=onlyTypes=true,useOptionals=all \
    "$@"
}

# transcript
java_gen transcript.proto
go_gen   transcript.proto
py_gen   transcript.proto
ruby_gen transcript.proto

# summary
go_gen   summary.proto
ruby_gen summary.proto

# action_items
py_gen   action_items.proto
ruby_gen action_items.proto

# bundle
ruby_gen bundle.proto

# web app: the bundle plus everything it embeds (one protoc run so the
# cross-file imports resolve to the sibling generated files)
web_gen proto/transcript.proto proto/summary.proto proto/action_items.proto proto/bundle.proto

# dtos (Temporal payloads). Backend workers use their SDK's default proto
# converter; workflow-ts/intake-ts use protobufjs via a custom converter.
java_gen dtos.proto
go_gen   dtos.proto
py_gen   dtos.proto
ruby_gen dtos.proto
# TypeScript: protobufjs json-module -> real Root for the converter.
for svc in workflow-ts intake-ts; do
  (cd "services/$svc" \
    && npx pbjs -t json-module -w commonjs -o src/proto/root.js ../../proto/dtos.proto \
    && npx pbts -o src/proto/root.d.ts src/proto/root.js)
done

echo "generated."
