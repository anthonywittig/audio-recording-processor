import { proxyActivities } from '@temporalio/workflow';
import type { Root } from 'protobufjs';
import { TASK_QUEUES, type ProcessAudioInput, type EmailResult } from './shared';

// protobufjs root for constructing Temporal payload DTOs. Bundled into the
// workflow (same root the converter uses). Constructing a message is
// deterministic, so this is workflow-safe.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const root = require('./proto/root') as unknown as Root;

// One activity proxy per task queue, so each call is dispatched to the worker
// written in the right language. Retry policies are per-step: transcription is
// long-running (async AWS Transcribe job) so it gets a generous timeout and a
// heartbeat; the rest are quick request/response calls.

// Every activity uses protobuf DTOs end-to-end: we send an arp.v1.*Input message
// and receive an arp.v1.*Result (decoded by the converter to a message whose
// camelCase fields we read below).
const { transcribeAudio } = proxyActivities<{
  transcribeAudio(input: unknown): Promise<{ transcriptKey: string }>;
}>({
  taskQueue: TASK_QUEUES.transcribe,
  startToCloseTimeout: '20 minutes',
  heartbeatTimeout: '2 minutes',
  retry: { maximumAttempts: 3 },
});

const { summarizeTranscript } = proxyActivities<{
  summarizeTranscript(input: unknown): Promise<{ summaryKey: string }>;
}>({
  taskQueue: TASK_QUEUES.summarize,
  startToCloseTimeout: '5 minutes',
  retry: { maximumAttempts: 3 },
});

const { extractActionItems } = proxyActivities<{
  extractActionItems(input: unknown): Promise<{ actionItemsKey: string }>;
}>({
  taskQueue: TASK_QUEUES.actionItems,
  startToCloseTimeout: '5 minutes',
  retry: { maximumAttempts: 3 },
});

const { sendEmail } = proxyActivities<{
  sendEmail(input: unknown): Promise<{ messageId: string }>;
}>({
  taskQueue: TASK_QUEUES.email,
  startToCloseTimeout: '2 minutes',
  retry: { maximumAttempts: 3 },
});

/**
 * Orchestrates the pipeline:
 *   audio → transcript → (summary ∥ action items) → email
 *
 * Summary and action items both depend only on the transcript, so they run
 * concurrently. Every step passes S3 keys, never file contents.
 */
export async function processAudio(input: ProcessAudioInput): Promise<EmailResult> {
  const transcribeInput = root
    .lookupType('arp.v1.TranscribeInput')
    .create({ bucket: input.bucket, audioKey: input.audioKey });
  const { transcriptKey } = await transcribeAudio(transcribeInput);

  const [summary, actionItems] = await Promise.all([
    summarizeTranscript(
      root.lookupType('arp.v1.SummarizeInput').create({ bucket: input.bucket, transcriptKey }),
    ),
    extractActionItems(
      root.lookupType('arp.v1.ActionItemsInput').create({ bucket: input.bucket, transcriptKey }),
    ),
  ]);

  return await sendEmail(
    root.lookupType('arp.v1.EmailInput').create({
      bucket: input.bucket,
      transcriptKey,
      summaryKey: summary.summaryKey,
      actionItemsKey: actionItems.actionItemsKey,
      recipientEmail: input.recipientEmail,
    }),
  );
}
