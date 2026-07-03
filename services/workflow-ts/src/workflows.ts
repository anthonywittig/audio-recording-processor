import { proxyActivities } from '@temporalio/workflow';
import {
  TASK_QUEUES,
  type Activities,
  type ProcessAudioInput,
  type EmailResult,
} from './shared';

// One activity proxy per task queue, so each call is dispatched to the worker
// written in the right language. Retry policies are per-step: transcription is
// long-running (async AWS Transcribe job) so it gets a generous timeout and a
// heartbeat; the rest are quick request/response calls.

const { transcribeAudio } = proxyActivities<Pick<Activities, 'transcribeAudio'>>({
  taskQueue: TASK_QUEUES.transcribe,
  startToCloseTimeout: '20 minutes',
  heartbeatTimeout: '2 minutes',
  retry: { maximumAttempts: 3 },
});

const { summarizeTranscript } = proxyActivities<Pick<Activities, 'summarizeTranscript'>>({
  taskQueue: TASK_QUEUES.summarize,
  startToCloseTimeout: '5 minutes',
  retry: { maximumAttempts: 3 },
});

const { extractActionItems } = proxyActivities<Pick<Activities, 'extractActionItems'>>({
  taskQueue: TASK_QUEUES.actionItems,
  startToCloseTimeout: '5 minutes',
  retry: { maximumAttempts: 3 },
});

const { sendEmail } = proxyActivities<Pick<Activities, 'sendEmail'>>({
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
  const { transcriptKey } = await transcribeAudio({
    bucket: input.bucket,
    audioKey: input.audioKey,
  });

  const [summary, actionItems] = await Promise.all([
    summarizeTranscript({ bucket: input.bucket, transcriptKey }),
    extractActionItems({ bucket: input.bucket, transcriptKey }),
  ]);

  return await sendEmail({
    bucket: input.bucket,
    transcriptKey,
    summaryKey: summary.summaryKey,
    actionItemsKey: actionItems.actionItemsKey,
    recipientEmail: input.recipientEmail,
  });
}
