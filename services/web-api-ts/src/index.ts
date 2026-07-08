// API for the web app, running as a single Lambda behind an HTTP API Gateway
// that CloudFront serves under /api/* next to the static site (one origin for
// the browser, so no CORS on the API itself).
//
// Audio bytes never pass through here: uploads and artifact downloads go
// straight to S3 with presigned URLs. This API only mints URLs and lists what
// exists, and it reuses the pipeline's key convention:
//   audio/<name>  ->  transcripts/<name>.json          (intermediate: status only)
//                 ->  bundles/<name>.bundle.json       (final: what the UI reads)
//
// Auth is a single shared passcode (header x-arp-passcode) checked against the
// arp/web-passcode secret — a one-user-POC posture. The presigned URLs are the
// actual S3 access control.

import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';
import {
  S3Client,
  ListObjectsV2Command,
  GetObjectCommand,
  PutObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { randomBytes, timingSafeEqual } from 'node:crypto';

const INGEST_BUCKET = process.env.INGEST_BUCKET!;
const PASSCODE_SECRET_ID = process.env.PASSCODE_SECRET_ID!;
const PRESIGN_TTL_SECONDS = 900;

const s3 = new S3Client({});
const secrets = new SecretsManagerClient({});

// ---- passcode auth ----

let cachedPasscode: { value: string; fetchedAt: number } | undefined;

async function passcode(): Promise<string> {
  if (!cachedPasscode || Date.now() - cachedPasscode.fetchedAt > 5 * 60_000) {
    const out = await secrets.send(new GetSecretValueCommand({ SecretId: PASSCODE_SECRET_ID }));
    // Trim: a `put-secret-value --secret-string file://...` easily picks up a
    // trailing newline, which would fail the exact comparison below.
    cachedPasscode = { value: (out.SecretString ?? '').trim(), fetchedAt: Date.now() };
  }
  return cachedPasscode.value;
}

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && timingSafeEqual(ab, bb);
}

async function authorized(event: APIGatewayProxyEventV2): Promise<boolean> {
  const given = event.headers['x-arp-passcode'] ?? '';
  const expected = await passcode();
  return expected.length > 0 && safeEqual(given, expected);
}

// ---- key convention (must match the workers' derive*Key functions) ----

function artifactKeys(audioKey: string) {
  const name = audioKey.startsWith('audio/') ? audioKey.slice('audio/'.length) : audioKey;
  return {
    transcript: `transcripts/${name}.json`,
    bundle: `bundles/${name}.bundle.json`,
  };
}

// The transcribe worker infers Transcribe's MediaFormat from the extension, so
// the extension must reflect what MediaRecorder actually produced.
function extensionFor(contentType: string): string {
  const base = contentType.split(';')[0].trim().toLowerCase();
  switch (base) {
    case 'audio/mp4':
    case 'audio/x-m4a':
    case 'audio/m4a':
    case 'video/mp4':
      return 'm4a';
    case 'audio/webm':
    case 'video/webm':
      return 'webm';
    case 'audio/mpeg':
      return 'mp3';
    case 'audio/wav':
    case 'audio/x-wav':
      return 'wav';
    case 'audio/ogg':
      return 'ogg';
    default:
      return 'm4a';
  }
}

// ---- handlers ----

async function createUpload(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  let contentType = 'audio/mp4';
  try {
    const body = JSON.parse(event.body ?? '{}');
    if (typeof body.contentType === 'string' && body.contentType) contentType = body.contentType;
  } catch {
    return json(400, { error: 'invalid JSON body' });
  }

  const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
  const audioKey = `audio/web-${stamp}-${randomBytes(3).toString('hex')}.${extensionFor(contentType)}`;

  const uploadUrl = await getSignedUrl(
    s3,
    new PutObjectCommand({ Bucket: INGEST_BUCKET, Key: audioKey, ContentType: contentType }),
    { expiresIn: PRESIGN_TTL_SECONDS },
  );

  return json(200, { audioKey, uploadUrl, contentType });
}

async function listPrefix(prefix: string): Promise<Map<string, { size: number; lastModified?: Date }>> {
  const found = new Map<string, { size: number; lastModified?: Date }>();
  let token: string | undefined;
  do {
    const out = await s3.send(
      new ListObjectsV2Command({ Bucket: INGEST_BUCKET, Prefix: prefix, ContinuationToken: token }),
    );
    for (const obj of out.Contents ?? []) {
      if (obj.Key && (obj.Size ?? 0) > 0) {
        found.set(obj.Key, { size: obj.Size ?? 0, lastModified: obj.LastModified });
      }
    }
    token = out.IsTruncated ? out.NextContinuationToken : undefined;
  } while (token);
  return found;
}

async function presignGet(key: string): Promise<string> {
  return getSignedUrl(s3, new GetObjectCommand({ Bucket: INGEST_BUCKET, Key: key }), {
    expiresIn: PRESIGN_TTL_SECONDS,
  });
}

async function listRecordings(): Promise<APIGatewayProxyResultV2> {
  let audio, transcripts, bundles;
  try {
    // The bundle (workflow's last step) is the only artifact the UI fetches;
    // transcripts/ is listed just to distinguish transcribing from analyzing.
    [audio, transcripts, bundles] = await Promise.all([
      listPrefix('audio/'),
      listPrefix('transcripts/'),
      listPrefix('bundles/'),
    ]);
  } catch (err: unknown) {
    // The ingest bucket lives in the (nightly-torn-down) poc stack; surface
    // that state instead of a 500 so the UI can say "pipeline is down".
    if ((err as { name?: string }).name === 'NoSuchBucket') {
      return json(200, { recordings: [], pipelineDown: true });
    }
    throw err;
  }

  const recordings = await Promise.all(
    [...audio.entries()]
      .sort((a, b) => (b[1].lastModified?.getTime() ?? 0) - (a[1].lastModified?.getTime() ?? 0))
      .map(async ([audioKey, meta]) => {
        const keys = artifactKeys(audioKey);
        const hasBundle = bundles.has(keys.bundle);
        const status = hasBundle
          ? 'done'
          : transcripts.has(keys.transcript)
            ? 'analyzing'
            : 'transcribing';

        const [audioUrl, bundleUrl] = await Promise.all([
          presignGet(audioKey),
          hasBundle ? presignGet(keys.bundle) : undefined,
        ]);

        return {
          audioKey,
          name: audioKey.slice('audio/'.length),
          size: meta.size,
          lastModified: meta.lastModified?.toISOString(),
          status,
          urls: { audio: audioUrl, bundle: bundleUrl },
        };
      }),
  );

  return json(200, { recordings });
}

// ---- routing ----

function json(statusCode: number, body: unknown): APIGatewayProxyResultV2 {
  return {
    statusCode,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
    body: JSON.stringify(body),
  };
}

export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  const method = event.requestContext.http.method;
  const path = event.rawPath;

  if (!(await authorized(event))) return json(401, { error: 'invalid passcode' });

  if (method === 'GET' && path === '/api/recordings') return listRecordings();
  if (method === 'POST' && path === '/api/recordings') return createUpload(event);

  return json(404, { error: 'not found' });
}
