// Thin client for the web-api Lambda (same origin, /api/*) plus the direct-to-S3
// presigned upload. The passcode lives in localStorage and rides along as the
// x-arp-passcode header on every API call.

export interface RecordingUrls {
  audio: string;
  transcript?: string;
  summary?: string;
  actionItems?: string;
}

export type RecordingStatus = 'transcribing' | 'analyzing' | 'done';

export interface Recording {
  audioKey: string;
  name: string;
  size: number;
  lastModified?: string;
  status: RecordingStatus;
  urls: RecordingUrls;
}

export interface ListResponse {
  recordings: Recording[];
  pipelineDown?: boolean;
}

const PASSCODE_KEY = 'arp-passcode';

export function storedPasscode(): string | null {
  return localStorage.getItem(PASSCODE_KEY);
}

export function storePasscode(value: string): void {
  localStorage.setItem(PASSCODE_KEY, value);
}

export function clearPasscode(): void {
  localStorage.removeItem(PASSCODE_KEY);
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    ...init,
    headers: {
      ...init?.headers,
      'x-arp-passcode': storedPasscode() ?? '',
      ...(init?.body ? { 'content-type': 'application/json' } : {}),
    },
  });
  if (!res.ok) throw new ApiError(res.status, `API ${res.status} on ${path}`);
  return (await res.json()) as T;
}

export function listRecordings(): Promise<ListResponse> {
  return api<ListResponse>('/api/recordings');
}

/** Mint a presigned URL, then PUT the recorded blob straight to S3. */
export async function uploadRecording(blob: Blob): Promise<string> {
  const contentType = blob.type || 'audio/mp4';
  const { audioKey, uploadUrl } = await api<{ audioKey: string; uploadUrl: string }>(
    '/api/recordings',
    { method: 'POST', body: JSON.stringify({ contentType }) },
  );

  // Content-Type must match what the URL was signed with.
  const put = await fetch(uploadUrl, {
    method: 'PUT',
    headers: { 'content-type': contentType },
    body: blob,
  });
  if (!put.ok) {
    throw new ApiError(put.status, `S3 upload failed (${put.status}) — is the poc stack up?`);
  }
  return audioKey;
}
