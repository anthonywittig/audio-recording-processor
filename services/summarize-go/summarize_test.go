package main

import (
	"context"
	"os"
	"testing"
)

// Live integration test for the summarize path. It exercises newActivities
// (AWS config load + Secrets Manager key read) and a real OpenAI call, but
// skips S3 and Temporal. Guarded so `go test` stays offline by default.
//
//   AWS_PROFILE=... AWS_REGION=us-east-1 \
//   OPENAI_SECRET_ID=arp/openai-api-key RUN_LIVE=1 \
//   go test -run TestSummarizeLive -v
func TestSummarizeLive(t *testing.T) {
	if os.Getenv("RUN_LIVE") == "" {
		t.Skip("set RUN_LIVE=1 (and AWS creds + OPENAI_SECRET_ID or OPENAI_API_KEY) to run")
	}

	ctx := context.Background()
	a, err := newActivities(ctx)
	if err != nil {
		t.Fatalf("newActivities: %v", err)
	}

	transcript := "spk_0: Morning everyone. We need to decide on the launch date. " +
		"spk_1: I think Friday works if QA signs off. " +
		"spk_0: Agreed, let's target Friday. Bob, can you own the release notes? " +
		"spk_1: Yes, I'll have them ready Thursday."

	summary, err := a.summarize(ctx, transcript)
	if err != nil {
		t.Fatalf("summarize: %v", err)
	}
	if summary == "" {
		t.Fatal("summarize returned empty string")
	}
	t.Logf("model=%s summary:\n%s", a.model, summary)
}
