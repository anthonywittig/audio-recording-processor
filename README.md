# audio-recording-processor

A learning-focused POC that orchestrates a **polyglot** audio-processing pipeline with
[Temporal](https://temporal.io) on **self-hosted EKS**. An audio file lands in S3 and a
Temporal workflow drives a chain of single-purpose activities — each deliberately written
in a different language:

| Step | Language | Does | AWS service |
|------|----------|------|-------------|
| Workflow definition | TypeScript | orchestrates the activities | — |
| Transcribe | Java | audio → transcript (with speaker diarization) | AWS Transcribe |
| Summarize | Go | transcript → summary | OpenAI |
| Action items | Python | transcript → action items | OpenAI |
| Email | Ruby | transcript+summary+actions → email | SES |
| Intake | TypeScript | S3 upload → starts the workflow | SQS |

Everything in AWS is **Terraform**. The whole stack is meant to be stood up and torn
down cheaply.

> Status: under construction. See `../.claude/plans/` for the build plan and the phase
> checklist below.

## Architecture

```
 upload audio ─▶ S3 ingest bucket
                     │ s3:ObjectCreated
                     ▼
                   SQS ──▶ intake service (in-cluster, Temporal CLIENT)
                                    │ startWorkflow
                                    ▼
                 ┌──────────────────────────────────────────────┐
                 │  Temporal server (EKS) + Postgres on RDS      │
                 │  no OpenSearch — advanced visibility on PG    │
                 └──────────────────────────────────────────────┘
                                    │
        TS Workflow Worker  (task queue: workflow)
           ├─ transcribe   → queue: transcribe   → Java worker  → S3
           ├─ summarize    → queue: summarize    → Go worker    → S3
           ├─ action-items → queue: action-items → Python worker→ S3
           └─ email        → queue: email        → Ruby worker  → SES
```

Activities pass **S3 keys**, not payloads, to stay under Temporal's message-size limits.

## Prerequisites

Install locally (macOS):

```bash
brew install terraform awscli kubernetes-cli helm gettext
brew install --cask docker      # or: brew install colima docker  (lighter)
aws configure                   # credentials + default region us-east-1
```

Runtimes for building the workers (already present on the dev machine): Node, Java+Maven,
Go, Python 3, Ruby+Bundler.

**One-time AWS console steps** (not doable in Terraform):
- **OpenAI API key** — the summarize (Go) and action-items (Python) workers call OpenAI.
  The key lives in Secrets Manager as `arp/openai-api-key`. It has already been created
  for this account, so Terraform must **adopt** it on first apply rather than recreate:
  ```bash
  terraform import aws_secretsmanager_secret.openai arp/openai-api-key
  # rotate the value anytime with:
  aws secretsmanager put-secret-value --secret-id arp/openai-api-key \
    --secret-string 'sk-...' --region us-east-1
  ```
  In-cluster the workers read it via IRSA (`OPENAI_SECRET_ID`); locally you can just
  export `OPENAI_API_KEY`. Model is env-configurable (`OPENAI_MODEL`, default
  `gpt-4o-mini`). Verified end-to-end via `go test -run TestSummarizeLive` in
  `services/summarize-go`.
  > Why not Bedrock: on this brand-new account, both Anthropic and Nova on-demand Bedrock
  > quotas are **0 tokens/day and non-adjustable** — an account-provisioning hold that
  > isn't self-serve fixable. Once AWS lifts it, Bedrock is a drop-in alternative.
- **SES (sending)** — the account starts in the SES *sandbox*. Verify the sender and
  recipient email identities (SES console → Verified identities). Sandbox is fine for the
  POC; no domain required. Summaries are always emailed to the fixed verified recipient
  (`RECIPIENT_EMAIL` on the intake deployment), regardless of who sent the audio in.
- **SES inbound DNS (Phase 6)** — receiving audio by email needs two DNS records on the
  `inbound_domain` (default `inbound.witski.com`), added by hand at the DNS provider
  since that zone is not in Route 53. After `terraform apply`, run:
  ```bash
  terraform output inbound_dns_records   # -> the exact TXT + MX records to add
  terraform output inbound_email_address # -> the secret address to send audio to
  ```
  Add the `_amazonses.<domain>` **TXT** (SES domain verification) and the `<domain>`
  **MX** (`10 inbound-smtp.us-east-1.amazonaws.com`). Receiving is inert until they
  propagate and SES marks the domain *verified*. The address has a random local part and
  is intentionally kept out of this repo — any sender is accepted, so the address is the
  only gate. See [Phase 6](#ses-inbound-email-phase-6).

## Layout

```
infra/terraform/
  bootstrap/   # creates the S3 remote-state bucket (run once, local state)
  poc/         # the actual stack: VPC, EKS, RDS, ECR, Temporal, workers
k8s/           # Helm values + worker manifests
services/      # one directory per worker (workflow-ts, transcribe-java, ...)
```

## Bring-up

```bash
# 1. Create the remote-state bucket (once).
cd infra/terraform/bootstrap
terraform init && terraform apply
#   -> note the state_bucket_name output; if you changed it, update ../poc/backend.tf

# 2. Stand up the stack.
cd ../poc
terraform init
terraform apply
#   -> writes kubeconfig access; then:
aws eks update-kubeconfig --name arp --region us-east-1
kubectl get nodes            # should show the managed node group, Ready
```

Terraform stops at the AWS layer. The in-cluster pieces are deployed separately:
the Temporal server via the helm CLI ([Temporal server](#temporal-server-phase-2))
and the workers via `./k8s/apply.sh` ([Deploying a worker](#deploying-a-worker-phase-4)).

## Teardown

```bash
cd infra/terraform/poc
terraform destroy

# then the state bucket (only when you're completely done):
cd ../bootstrap
terraform destroy
```

**Verify nothing billable lingers** (Terraform can't always catch controller-created
resources): check the console for stray **Load Balancers**, **NAT gateways / EIPs**,
**EBS volumes**, and **ECR images**. SES identities cost nothing
to leave enabled. `terraform destroy` removes the SES receipt rule set and inbound
resources, but the **inbound DNS records** (TXT + MX) live at the external DNS provider —
remove those by hand.

## Cost watch-list (~monthly, us-east-1, POC scale)

| Item | Approx |
|------|--------|
| EKS control plane | ~$73 |
| 2× t3.medium nodes | ~$60 |
| RDS db.t4g.micro | ~$12 |
| **NAT gateway (single)** | **~$32** ← biggest avoidable |
| ECR / S3 / SQS / Lambda / Transcribe / SES / OpenAI | pennies at POC volume |

## Temporal server (Phase 2)

Deployed with the `temporalio/temporal` Helm chart (1.5.0 / Temporal 1.31.1),
configured for external RDS Postgres and SQL visibility (advanced visibility on
Postgres 12+, so **no OpenSearch**). Values: [k8s/temporal-values.yaml](k8s/temporal-values.yaml).

```bash
# namespace + DB password secret (password pulled from Secrets Manager)
kubectl create namespace temporal
PW=$(aws secretsmanager get-secret-value --secret-id arp/temporal-db \
  --query SecretString --output text | python3 -c "import sys,json;print(json.load(sys.stdin)['password'])")
kubectl create secret generic temporal-db -n temporal --from-literal=password="$PW"

helm repo add temporalio https://go.temporal.io/helm-charts && helm repo update
helm install temporal temporalio/temporal -n temporal --version 1.5.0 \
  -f k8s/temporal-values.yaml --timeout 6m

# register the app namespace the workers use
kubectl exec -n temporal deploy/temporal-admintools -- \
  temporal operator namespace create --address temporal-frontend:7233 --retention 72h default
```

- **RDS requires SSL** (`rds.force_ssl=1`), so each datastore sets `tls.enabled: true`
  with `enableHostVerification: false` (encrypt without shipping the RDS CA). Without
  this the schema-setup hook fails with `no pg_hba.conf entry ... no encryption`.
- The `connectAddr` in the values file is the RDS endpoint from `terraform output`; update
  it if the DB is recreated.
- **Web UI** is internal (ClusterIP `temporal-web:8080`), nothing is exposed publicly.
  Reach it with a port-forward:
  ```bash
  kubectl port-forward -n temporal svc/temporal-web 8233:8080
  ```
  Then open http://localhost:8233 — workflow runs are under the `default` namespace:
  http://localhost:8233/namespaces/default/workflows. Each `processAudio` run shows the
  activity timeline (`transcribeAudio → summarizeTranscript ∥ extractActionItems →
  sendEmail`), the protobuf payloads at each step, and any retries. Note the UI is not
  read-only — you can terminate/signal workflows from it.

  `kubectl port-forward` drops the streamed connection on idle (`error: lost connection to
  pod`); wrap it to auto-reconnect if you want it to stay up:
  ```bash
  while true; do kubectl port-forward -n temporal svc/temporal-web 8233:8080; sleep 1; done
  ```

## Deploying a worker (Phase 4)

Each worker follows the same path — build an image, push to its ECR repo, apply a
Deployment whose ServiceAccount is IRSA-bound to a least-privilege role. The
summarize (Go) worker is the reference:

```bash
ECR=$(terraform -chdir=infra/terraform/poc output -raw account_id).dkr.ecr.us-east-1.amazonaws.com
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR
# IMPORTANT: nodes are amd64; build for that platform or the pod crashes (exec format error)
docker build --platform linux/amd64 -t $ECR/arp/summarize-go:latest services/summarize-go
docker push $ECR/arp/summarize-go:latest
```

The manifests live in `k8s/workers/*.yaml.tmpl` (templates, so no AWS account ID
is committed). Render and apply them all — namespace first — with:

```bash
./k8s/apply.sh
```

`apply.sh` fills `${AWS_ACCOUNT_ID}` / `${AWS_REGION}` from `terraform output`
(the single source of truth), or from a gitignored `k8s/config.env` if you'd
rather not hit Terraform (copy `k8s/config.env.example`). Requires `envsubst`
(`brew install gettext`).

> The `account_id` output only lands in Terraform state after a `terraform
> apply` runs (adding an output doesn't update state on its own). Until then
> `apply.sh`'s default path fails with `Output "account_id" not found` — run
> `terraform -chdir=infra/terraform/poc apply` once (an outputs-only change, no
> infra touched), or use `k8s/config.env`.

- Workers run in the `arp` namespace and reach Temporal at
  `temporal-frontend.temporal.svc:7233` (cross-namespace, frontend stays internal).
- IRSA roles live in [infra/terraform/poc/irsa.tf](infra/terraform/poc/irsa.tf); the SA
  annotation's role ARN must match, and the role's trust policy pins the exact
  `namespace:serviceaccount`.
- Verify a worker is polling: `kubectl exec -n temporal deploy/temporal-admintools --
  temporal task-queue describe --address temporal-frontend:7233 -n default --task-queue summarize`.

## Shared S3 schemas (protobuf)

Every S3 artifact the pipeline produces is defined once in [proto/](proto/) and stored as
**proto-JSON** (proto3's canonical JSON mapping) — human-readable files, single source of
truth for each shape, generated per-language:

| Artifact | proto | Writer | Readers |
|----------|-------|--------|---------|
| transcript | `transcript.proto` | Java | Go, Python, Ruby |
| summary | `summary.proto` | Go | Ruby |
| action items | `action_items.proto` | Python | Ruby |

Writers use "always print fields" and readers ignore unknown fields so the languages agree
byte-for-byte. (`transcribe-raw/` objects are AWS Transcribe's own output, not ours.)

Generated code is committed (builds don't need `protoc`). Regenerate after editing the
proto:

```bash
brew install protobuf
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
bash proto/gen.sh
```

The **Temporal-payload DTOs** (the workflow input + every activity's args/results) are
also protobuf, defined in [proto/dtos.proto](proto/dtos.proto). Backend workers
(Java/Go/Python/Ruby) use their SDK's built-in protobuf payload converter; `workflow-ts`
and `intake-ts` use a custom converter (`DefaultPayloadConverterWithProtobufs` over a
protobufjs json-module root, with `bundlerOptions.ignoreModules: ['fs']` for the workflow
sandbox). So every payload the pipeline moves — S3 files and Temporal payloads alike — is
protobuf-defined.

## SES inbound email (Phase 6)

Get an audio recording from a phone into the pipeline with zero client: share a voice
memo → Mail → send it to the (secret) inbound address.

```
email w/ audio ─▶ SES receiving (MX on inbound.witski.com)
                     │ receipt rule (matches the one secret recipient)
                     ▼
              s3://arp-inbound-<acct>/raw/…  (raw MIME)
                     │ s3:ObjectCreated
                     ▼
              inbound-parser Lambda (Python, stdlib email)
                     │ extract first audio attachment
                     ▼
              s3://arp-ingest-<acct>/audio/…  ──▶ Phase 5 path (SQS → intake → workflow)
```

- Terraform: [ses-inbound.tf](infra/terraform/poc/ses-inbound.tf). Lambda source:
  [services/inbound-parser-py](services/inbound-parser-py) (packaged via `archive_file`,
  no build step).
- A separate `arp-inbound-<acct>` bucket holds raw MIME (7-day lifecycle expiry) so the
  ingest bucket's `audio/` notification stays untouched.
- The recipient address has a random local part (Terraform `random_id`, state-only) and
  is **not** in this repo. Any sender is accepted, so the address is the only gate.
- Requires the TXT + MX DNS records from [Prerequisites](#prerequisites); until they
  propagate and SES verifies the domain, inbound mail is rejected/dropped.
- SES receiving max message size is 40 MB (fine for voice memos). Attachments must be a
  format AWS Transcribe accepts (m4a, mp3, mp4, wav, flac, ogg, amr, webm).

## Build phases

- [x] **0** — Scaffolding & Terraform remote state
- [x] **1** — Core AWS infra (VPC, EKS, RDS, ECR)
- [x] **2** — Temporal server via Helm (external RDS, no OpenSearch)
- [x] **3** — TS workflow worker + stub activities (prove routing)
- [x] **4** — Polyglot activity workers (Java, Go, Python, Ruby) — deployed; full pipeline verified end-to-end (audio → transcript → summary + action items → email)
- [x] **5** — Automatic S3 intake (upload → S3 event → SQS → intake-ts starts the workflow) — verified end-to-end
- [x] **6** — SES inbound email (email an audio attachment → SES receipt rule → raw MIME to `arp-inbound-<acct>` → `inbound-parser` Lambda extracts the attachment into `audio/` → the Phase 5 path runs). Gated on the two DNS records above.
