import { NativeConnection, Worker } from '@temporalio/worker';
import { TASK_QUEUES } from './shared';
import * as stubs from './activities-stub';

// Runs one Temporal Worker per activity task queue, each backed by the stub
// implementation. This single process stands in for all the polyglot workers
// during Phase 3. As each real worker lands (Phase 4), stop registering the
// corresponding stub here (or just let the real worker on that queue win by
// scaling this process's coverage down).

const REGISTRY = [
  { taskQueue: TASK_QUEUES.transcribe, activities: { transcribeAudio: stubs.transcribeAudio } },
  { taskQueue: TASK_QUEUES.summarize, activities: { summarizeTranscript: stubs.summarizeTranscript } },
  { taskQueue: TASK_QUEUES.actionItems, activities: { extractActionItems: stubs.extractActionItems } },
  { taskQueue: TASK_QUEUES.bundle, activities: { bundleResults: stubs.bundleResults } },
];

async function run(): Promise<void> {
  const address = process.env.TEMPORAL_ADDRESS ?? 'localhost:7233';
  const namespace = process.env.TEMPORAL_NAMESPACE ?? 'default';

  const connection = await NativeConnection.connect({ address });

  const workers = await Promise.all(
    REGISTRY.map(({ taskQueue, activities }) =>
      Worker.create({
        connection,
        namespace,
        taskQueue,
        activities,
        dataConverter: { payloadConverterPath: require.resolve('./payload-converter') },
      }),
    ),
  );

  console.log(
    `stub workers started on queues: ${REGISTRY.map((r) => r.taskQueue).join(', ')}`,
  );
  await Promise.all(workers.map((w) => w.run()));
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
