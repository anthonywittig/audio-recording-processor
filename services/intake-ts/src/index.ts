import { Client, Connection, WorkflowExecutionAlreadyStartedError } from '@temporalio/client';
import {
  SQSClient,
  ReceiveMessageCommand,
  DeleteMessageCommand,
} from '@aws-sdk/client-sqs';
import type { Root } from 'protobufjs';

// eslint-disable-next-line @typescript-eslint/no-require-imports
const root = require('./proto/root') as unknown as Root;

// Task queue + workflow type must match the TS workflow worker
// (services/workflow-ts). Starting by type name avoids bundling workflow code.
const TASK_QUEUE = 'workflow';
const WORKFLOW_TYPE = 'processAudio';

interface S3EventRecord {
  eventTime?: string;
  s3?: { bucket?: { name?: string }; object?: { key?: string } };
}

async function main(): Promise<void> {
  const address = process.env.TEMPORAL_ADDRESS ?? 'localhost:7233';
  const namespace = process.env.TEMPORAL_NAMESPACE ?? 'default';
  const queueUrl = process.env.INTAKE_QUEUE_URL;
  const recipient = process.env.RECIPIENT_EMAIL ?? 'someone@example.com';
  if (!queueUrl) {
    throw new Error('INTAKE_QUEUE_URL is required');
  }

  const sqs = new SQSClient({});
  const connection = await Connection.connect({ address });
  const client = new Client({
    connection,
    namespace,
    dataConverter: { payloadConverterPath: require.resolve('./payload-converter') },
  });

  let running = true;
  const stop = () => {
    running = false;
  };
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);

  console.log(`intake started: queue=${queueUrl} temporal=${address}/${namespace} recipient=${recipient}`);

  while (running) {
    const res = await sqs.send(
      new ReceiveMessageCommand({
        QueueUrl: queueUrl,
        MaxNumberOfMessages: 10,
        WaitTimeSeconds: 20, // long poll
      }),
    );

    for (const msg of res.Messages ?? []) {
      try {
        await handleBody(client, recipient, msg.Body ?? '');
        // Delete on success (or benign duplicate / non-audio / S3 test event).
        await sqs.send(
          new DeleteMessageCommand({ QueueUrl: queueUrl, ReceiptHandle: msg.ReceiptHandle! }),
        );
      } catch (err) {
        // Leave the message for redelivery after the visibility timeout.
        console.error('failed to handle message, will retry:', err);
      }
    }
  }

  await connection.close();
}

async function handleBody(client: Client, recipient: string, body: string): Promise<void> {
  const event = JSON.parse(body) as { Records?: S3EventRecord[]; Event?: string };

  // S3 sends an s3:TestEvent (no Records) when the notification is first wired.
  const records = event.Records ?? [];
  for (const record of records) {
    const bucket = record.s3?.bucket?.name;
    const rawKey = record.s3?.object?.key;
    if (!bucket || !rawKey) continue;

    // S3 keys are URL-encoded in event notifications.
    const audioKey = decodeURIComponent(rawKey.replace(/\+/g, ' '));
    if (!audioKey.startsWith('audio/')) continue;

    // Stable id per (object, eventTime) so duplicate deliveries of the same
    // event dedupe; a re-upload has a new eventTime and runs again.
    const workflowId = `intake-${audioKey}-${record.eventTime ?? ''}`.replace(
      /[^a-zA-Z0-9_\-.]/g,
      '_',
    );

    try {
      const input = root
        .lookupType('arp.v1.ProcessAudioInput')
        .create({ bucket, audioKey, recipientEmail: recipient });
      await client.workflow.start(WORKFLOW_TYPE, {
        taskQueue: TASK_QUEUE,
        workflowId,
        args: [input],
      });
      console.log(`started ${workflowId} for s3://${bucket}/${audioKey}`);
    } catch (err) {
      if (err instanceof WorkflowExecutionAlreadyStartedError) {
        console.log(`duplicate event for ${workflowId}, skipping`);
      } else {
        throw err;
      }
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
