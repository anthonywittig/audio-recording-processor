import type {
  TranscribeInput,
  TranscribeResult,
  SummarizeInput,
  SummarizeResult,
  ActionItemsInput,
  ActionItemsResult,
  BundleInput,
  BundleResult,
} from './shared';

// Phase-3 stand-ins for the real polyglot activity workers. They return
// plausible S3 keys without touching AWS, so we can prove the workflow wiring
// and cross-queue routing before Java/Go/Python exist. Each real worker
// (Phase 4) replaces one of these by registering the same activity name on the
// same task queue; delete this file's usage as they come online.

export async function transcribeAudio(input: TranscribeInput): Promise<TranscribeResult> {
  const transcriptKey = input.audioKey.replace(/^audio\//, 'transcripts/') + '.transcript.json';
  console.log(`[stub] transcribeAudio ${input.audioKey} -> ${transcriptKey}`);
  return { transcriptKey };
}

export async function summarizeTranscript(input: SummarizeInput): Promise<SummarizeResult> {
  const summaryKey = input.transcriptKey.replace(/^transcripts\//, 'summaries/') + '.summary.txt';
  console.log(`[stub] summarizeTranscript ${input.transcriptKey} -> ${summaryKey}`);
  return { summaryKey };
}

export async function extractActionItems(input: ActionItemsInput): Promise<ActionItemsResult> {
  const actionItemsKey =
    input.transcriptKey.replace(/^transcripts\//, 'action-items/') + '.actions.json';
  console.log(`[stub] extractActionItems ${input.transcriptKey} -> ${actionItemsKey}`);
  return { actionItemsKey };
}

export async function bundleResults(input: BundleInput): Promise<BundleResult> {
  const bundleKey = input.transcriptKey.replace(/^transcripts\//, 'bundles/') + '.bundle.json';
  console.log(`[stub] bundleResults ${input.transcriptKey} -> ${bundleKey}`);
  return { bundleKey };
}
