"""Temporal activity for the `action-items` task queue.

Reads a transcript from S3, extracts concrete action items via OpenAI, and
writes them back to S3. The activity is registered as "extractActionItems" to
match the TS workflow's activity type (the Python SDK would otherwise use the
function name, and camelCase alignment across languages matters).
"""

import json
import os
from dataclasses import dataclass

import boto3
import requests
from google.protobuf import json_format
from temporalio import activity

import transcript_pb2


# Input/output shapes mirror services/workflow-ts/src/shared.ts. Dataclass field
# names are the cross-language JSON contract, so they must match exactly.
@dataclass
class ActionItemsInput:
    bucket: str
    transcriptKey: str


@dataclass
class ActionItemsResult:
    actionItemsKey: str


def _region():
    """Resolve the AWS region explicitly so boto3 never depends on env-var
    precedence quirks (in-cluster this comes from the pod's AWS_REGION)."""
    return os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")


def resolve_api_key() -> str:
    """Prefer OPENAI_API_KEY (local dev); otherwise read the key from Secrets
    Manager at OPENAI_SECRET_ID (the in-cluster path, authorized via IRSA)."""
    key = os.environ.get("OPENAI_API_KEY")
    if key:
        return key
    secret_id = os.environ.get("OPENAI_SECRET_ID")
    if not secret_id:
        raise RuntimeError("set OPENAI_API_KEY (local) or OPENAI_SECRET_ID (Secrets Manager)")
    resp = boto3.client("secretsmanager", region_name=_region()).get_secret_value(SecretId=secret_id)
    return resp["SecretString"].strip()


class ActionItemsActivities:
    def __init__(self, api_key: str, model: str, base_url: str):
        self._api_key = api_key
        self._model = model
        self._base_url = base_url
        self._s3 = boto3.client("s3", region_name=_region())

    @activity.defn(name="extractActionItems")
    def extract_action_items(self, input: ActionItemsInput) -> ActionItemsResult:
        text = self._read_transcript_text(input.bucket, input.transcriptKey)
        items = self.extract_items(text)
        key = _derive_key(input.transcriptKey)
        self._put_json(input.bucket, key, {"actionItems": items})
        return ActionItemsResult(actionItemsKey=key)

    def extract_items(self, transcript_text: str) -> list:
        """Call OpenAI and return a list of action-item strings. Kept separate
        from S3/Temporal so it can be exercised directly in a live check."""
        body = {
            "model": self._model,
            "messages": [
                {
                    "role": "system",
                    "content": "You extract concrete, actionable follow-up items from meeting transcripts.",
                },
                {
                    "role": "user",
                    "content": (
                        "From the transcript below, list the concrete action items. "
                        'Respond as JSON of the form {"actionItems": ["...", ...]}. '
                        "Use an empty array if there are none.\n\n" + transcript_text
                    ),
                },
            ],
            "response_format": {"type": "json_object"},
        }
        resp = requests.post(
            f"{self._base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {self._api_key}",
                "Content-Type": "application/json",
            },
            json=body,
            timeout=60,
        )
        resp.raise_for_status()
        content = resp.json()["choices"][0]["message"]["content"]
        parsed = json.loads(content)
        items = parsed.get("actionItems", [])
        return [str(i) for i in items]

    def _read_transcript_text(self, bucket: str, key: str) -> str:
        # The transcript is proto-JSON (proto/transcript.proto); parse it into
        # the generated Transcript message. ignore_unknown_fields keeps us
        # forward-compatible if new fields are added upstream.
        obj = self._s3.get_object(Bucket=bucket, Key=key)
        transcript = json_format.Parse(
            obj["Body"].read().decode("utf-8"),
            transcript_pb2.Transcript(),
            ignore_unknown_fields=True,
        )
        return transcript.text

    def _put_json(self, bucket: str, key: str, value: dict) -> None:
        self._s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(value).encode("utf-8"),
            ContentType="application/json",
        )


def _derive_key(transcript_key: str) -> str:
    """Map transcripts/<name>.json -> action-items/<name>.actions.json."""
    base = transcript_key
    if base.startswith("transcripts/"):
        base = base[len("transcripts/"):]
    if base.endswith(".json"):
        base = base[: -len(".json")]
    return f"action-items/{base}.actions.json"
