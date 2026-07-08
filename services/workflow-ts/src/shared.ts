// Shared contract between the workflow and the (polyglot) activity workers.
//
// IMPORTANT: the activity *names* and their input/output shapes below are the
// wire contract. The Java/Go/Python workers must register activities under
// these exact names and read/write these exact JSON fields. Temporal serializes
// activity args/results as JSON, so field names matter across languages.

/** Task queues. Each activity worker polls its own queue; the workflow worker
 *  polls `workflow`. Keep these strings in sync with the other services. */
export const TASK_QUEUES = {
  workflow: 'workflow',
  transcribe: 'transcribe',
  summarize: 'summarize',
  actionItems: 'action-items',
  bundle: 'bundle',
} as const;

/** Input to the top-level workflow. */
export interface ProcessAudioInput {
  /** S3 bucket holding the audio file (and where outputs are written). */
  bucket: string;
  /** S3 key of the uploaded audio file. */
  audioKey: string;
}

/** Workflow result: where every artifact landed. Plain JSON (the converter
 *  falls back to JSON for non-proto values); results are read via S3, so this
 *  is informational — visible in the Temporal UI. */
export interface ProcessAudioResult {
  transcriptKey: string;
  summaryKey: string;
  actionItemsKey: string;
  bundleKey: string;
}

// ---- Activity input/output shapes (S3 keys, never payloads) ----

export interface TranscribeInput {
  bucket: string;
  audioKey: string;
}
export interface TranscribeResult {
  transcriptKey: string;
}

export interface SummarizeInput {
  bucket: string;
  transcriptKey: string;
}
export interface SummarizeResult {
  summaryKey: string;
}

export interface ActionItemsInput {
  bucket: string;
  transcriptKey: string;
}
export interface ActionItemsResult {
  actionItemsKey: string;
}

export interface BundleInput {
  bucket: string;
  transcriptKey: string;
  summaryKey: string;
  actionItemsKey: string;
}
export interface BundleResult {
  bundleKey: string;
}

/** The full set of activity signatures, keyed by their registered names. */
export interface Activities {
  transcribeAudio(input: TranscribeInput): Promise<TranscribeResult>;
  summarizeTranscript(input: SummarizeInput): Promise<SummarizeResult>;
  extractActionItems(input: ActionItemsInput): Promise<ActionItemsResult>;
  bundleResults(input: BundleInput): Promise<BundleResult>;
}
