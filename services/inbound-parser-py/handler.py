"""SES inbound-email parser (AWS Lambda).

Triggered when SES writes a raw MIME message to the inbound bucket under raw/.
Pulls the first audio attachment out of the message and drops it into the ingest
bucket's audio/ prefix, where the existing Phase 5 path (S3 -> SQS -> intake ->
processAudio workflow) takes over.

Stdlib only (email, urllib) plus boto3, which the Lambda runtime provides — so the
deployment package is just this file, no build step.
"""

import email
import os
import re
import uuid
from urllib.parse import unquote_plus

import boto3

s3 = boto3.client("s3")

INGEST_BUCKET = os.environ["INGEST_BUCKET"]
AUDIO_PREFIX = os.environ.get("AUDIO_PREFIX", "audio/")

# Extensions AWS Transcribe accepts (the transcribe-java worker runs next).
AUDIO_EXTS = (
    ".m4a", ".mp3", ".mp4", ".wav", ".flac", ".ogg", ".amr", ".webm", ".aac",
)

# MIME subtype -> file extension for parts that arrive without a filename.
_SUBTYPE_EXT = {"mpeg": "mp3", "x-m4a": "m4a", "mp4": "m4a", "x-wav": "wav"}


def _is_audio(part):
    """True if this MIME part looks like an audio recording.

    iOS Voice Memos attach .m4a as audio/* or sometimes video/mp4, so we check the
    content type and fall back to the filename extension.
    """
    ctype = (part.get_content_type() or "").lower()
    if ctype.startswith("audio/") or ctype == "video/mp4":
        return True
    filename = (part.get_filename() or "").lower()
    return filename.endswith(AUDIO_EXTS)


def _safe_name(part):
    name = part.get_filename()
    if not name:
        sub = (part.get_content_subtype() or "bin").lower()
        name = f"recording.{_SUBTYPE_EXT.get(sub, sub)}"
    name = os.path.basename(name)
    return re.sub(r"[^A-Za-z0-9._-]", "_", name) or "recording"


def _handle_object(bucket, key):
    raw = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    msg = email.message_from_bytes(raw)

    found = 0
    for part in msg.walk():
        if part.get_content_maintype() == "multipart" or not _is_audio(part):
            continue
        payload = part.get_payload(decode=True)
        if not payload:
            continue
        dest_key = f"{AUDIO_PREFIX}{uuid.uuid4().hex}-{_safe_name(part)}"
        s3.put_object(Bucket=INGEST_BUCKET, Key=dest_key, Body=payload)
        print(f"wrote s3://{INGEST_BUCKET}/{dest_key} ({len(payload)} bytes) from {key}")
        found += 1

    if found == 0:
        print(f"no audio attachment in s3://{bucket}/{key}")


def handler(event, _context):
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])
        _handle_object(bucket, key)
    return {"ok": True}
