import { NativeConnection, Worker } from '@temporalio/worker';
import { TASK_QUEUES } from './shared';

// The workflow worker. It hosts ONLY the workflow code and polls the `workflow`
// task queue. It registers no activities — those live in the per-language
// activity workers on their own queues.

async function run(): Promise<void> {
  const address = process.env.TEMPORAL_ADDRESS ?? 'localhost:7233';
  const namespace = process.env.TEMPORAL_NAMESPACE ?? 'default';

  const connection = await NativeConnection.connect({ address });

  const worker = await Worker.create({
    connection,
    namespace,
    taskQueue: TASK_QUEUES.workflow,
    workflowsPath: require.resolve('./workflows'),
  });

  console.log(
    `workflow worker started: address=${address} namespace=${namespace} queue=${TASK_QUEUES.workflow}`,
  );
  await worker.run();
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
