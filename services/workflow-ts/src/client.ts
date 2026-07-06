import { Client, Connection } from '@temporalio/client';
import type { Root } from 'protobufjs';
import { processAudio } from './workflows';
import { TASK_QUEUES, type ProcessAudioInput } from './shared';

// eslint-disable-next-line @typescript-eslint/no-require-imports
const root = require('./proto/root') as unknown as Root;

// Manually start one workflow run. Handy for Phase 3 verification before the
// S3/SQS intake service exists. Reads inputs from env with sensible defaults.
//
//   TEMPORAL_ADDRESS=localhost:7233 \
//   BUCKET=my-bucket AUDIO_KEY=audio/sample.mp3 RECIPIENT=me@example.com \
//   npm run start-workflow

async function run(): Promise<void> {
  const address = process.env.TEMPORAL_ADDRESS ?? 'localhost:7233';
  const namespace = process.env.TEMPORAL_NAMESPACE ?? 'default';

  const bucket = process.env.BUCKET ?? 'arp-ingest-placeholder';
  const audioKey = process.env.AUDIO_KEY ?? 'audio/sample.mp3';
  const recipientEmail = process.env.RECIPIENT ?? 'someone@example.com';

  const connection = await Connection.connect({ address });
  const client = new Client({
    connection,
    namespace,
    dataConverter: { payloadConverterPath: require.resolve('./payload-converter') },
  });

  // Send the workflow input as a protobuf message (encoded by the converter).
  const input = root
    .lookupType('arp.v1.ProcessAudioInput')
    .create({ bucket, audioKey, recipientEmail });

  const handle = await client.workflow.start(processAudio, {
    taskQueue: TASK_QUEUES.workflow,
    workflowId: `process-audio-${audioKey}-${Date.now()}`,
    args: [input as unknown as ProcessAudioInput],
  });

  console.log(`started workflow ${handle.workflowId}; waiting for result...`);
  const result = await handle.result();
  console.log('workflow completed:', result);
  await connection.close();
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
