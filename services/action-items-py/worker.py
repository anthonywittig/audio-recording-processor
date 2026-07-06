"""action-items worker: polls the `action-items` task queue and runs the
extractActionItems activity. Activities are synchronous (boto3/requests block),
so they run in a thread pool executor."""

import asyncio
import os
from concurrent.futures import ThreadPoolExecutor

from temporalio.client import Client
from temporalio.worker import Worker

from activities import ActionItemsActivities, resolve_api_key

TASK_QUEUE = "action-items"


async def main() -> None:
    address = os.environ.get("TEMPORAL_ADDRESS", "localhost:7233")
    namespace = os.environ.get("TEMPORAL_NAMESPACE", "default")

    activities = ActionItemsActivities(
        api_key=resolve_api_key(),
        model=os.environ.get("OPENAI_MODEL", "gpt-4o-mini"),
        base_url=os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1"),
    )

    client = await Client.connect(address, namespace=namespace)

    with ThreadPoolExecutor(max_workers=10) as executor:
        worker = Worker(
            client,
            task_queue=TASK_QUEUE,
            activities=[activities.extract_action_items],
            activity_executor=executor,
            max_concurrent_activities=10,
        )
        print(f"action-items worker started: address={address} namespace={namespace} queue={TASK_QUEUE}")
        await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
