// summarize-go is the Temporal activity worker for the `summarize` task queue.
// It reads a transcript from S3, asks Claude (via AWS Bedrock) for a summary,
// and writes the summary back to S3. It registers a single activity under the
// name "summarizeTranscript", matching the wire contract in
// services/workflow-ts/src/shared.ts.
package main

import (
	"context"
	"log"
	"os"

	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/worker"
)

const taskQueue = "summarize"

func main() {
	address := getenv("TEMPORAL_ADDRESS", "localhost:7233")
	namespace := getenv("TEMPORAL_NAMESPACE", "default")

	c, err := client.Dial(client.Options{HostPort: address, Namespace: namespace})
	if err != nil {
		log.Fatalf("dial temporal: %v", err)
	}
	defer c.Close()

	acts, err := newActivities(context.Background())
	if err != nil {
		log.Fatalf("init activities: %v", err)
	}

	w := worker.New(c, taskQueue, worker.Options{})
	w.RegisterActivityWithOptions(acts.SummarizeTranscript, activity.RegisterOptions{Name: "summarizeTranscript"})

	log.Printf("summarize worker started: address=%s namespace=%s queue=%s", address, namespace, taskQueue)
	if err := w.Run(worker.InterruptCh()); err != nil {
		log.Fatalf("worker run: %v", err)
	}
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
