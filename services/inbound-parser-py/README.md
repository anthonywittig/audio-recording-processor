# inbound-parser-py

AWS Lambda (Python, stdlib only) for the **SES inbound email** intake path (Phase 6).

SES receives an email at the (secret) inbound address, stores the raw MIME message in
the `arp-inbound-<account>` bucket under `raw/`, and that put triggers this function.
It walks the MIME parts, pulls out the first audio attachment, and writes it to the
ingest bucket under `audio/` — where the existing S3 → SQS → `intake-ts` → `processAudio`
path takes over.

- Handler: `handler.handler`
- Runtime: `python3.12` (boto3 provided by the runtime; no dependencies to vendor)
- Env: `INGEST_BUCKET` (required), `AUDIO_PREFIX` (default `audio/`)

Packaged and deployed by Terraform (`infra/terraform/poc/ses-inbound.tf`) via
`archive_file` — there is no separate build step.
