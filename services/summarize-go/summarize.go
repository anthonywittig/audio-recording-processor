package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

// SummarizeInput / SummarizeResult mirror the shapes in
// services/workflow-ts/src/shared.ts. JSON field names are the cross-language
// contract, so they must match exactly.
type SummarizeInput struct {
	Bucket        string `json:"bucket"`
	TranscriptKey string `json:"transcriptKey"`
}

type SummarizeResult struct {
	SummaryKey string `json:"summaryKey"`
}

// Transcript is the normalized shape written by the Java transcribe worker.
// Only Text is needed here, but the full shape is documented for clarity.
type Transcript struct {
	AudioKey string              `json:"audioKey"`
	Language string              `json:"language"`
	Text     string              `json:"text"`
	Segments []TranscriptSegment `json:"segments"`
}

type TranscriptSegment struct {
	Speaker   string  `json:"speaker"`
	StartTime float64 `json:"startTime"`
	EndTime   float64 `json:"endTime"`
	Text      string  `json:"text"`
}

type activities struct {
	s3      *s3.Client
	http    *http.Client
	apiKey  string
	model   string
	baseURL string
}

func newActivities(ctx context.Context) (*activities, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}

	apiKey, err := resolveAPIKey(ctx, cfg)
	if err != nil {
		return nil, err
	}

	return &activities{
		s3:      s3.NewFromConfig(cfg),
		http:    &http.Client{Timeout: 60 * time.Second},
		apiKey:  apiKey,
		model:   getenv("OPENAI_MODEL", "gpt-4o-mini"),
		baseURL: getenv("OPENAI_BASE_URL", "https://api.openai.com/v1"),
	}, nil
}

// resolveAPIKey prefers OPENAI_API_KEY (handy for local dev) and otherwise
// reads the key from Secrets Manager at OPENAI_SECRET_ID (the in-cluster path,
// authorized via IRSA). The secret's value is the raw API key string.
func resolveAPIKey(ctx context.Context, cfg aws.Config) (string, error) {
	if k := os.Getenv("OPENAI_API_KEY"); k != "" {
		return k, nil
	}
	secretID := os.Getenv("OPENAI_SECRET_ID")
	if secretID == "" {
		return "", fmt.Errorf("set OPENAI_API_KEY (local) or OPENAI_SECRET_ID (Secrets Manager)")
	}
	sm := secretsmanager.NewFromConfig(cfg)
	out, err := sm.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{SecretId: &secretID})
	if err != nil {
		return "", fmt.Errorf("get secret %s: %w", secretID, err)
	}
	if out.SecretString == nil {
		return "", fmt.Errorf("secret %s has no string value", secretID)
	}
	return strings.TrimSpace(*out.SecretString), nil
}

// SummarizeTranscript reads the transcript from S3, summarizes it with OpenAI,
// and writes the summary JSON back to S3, returning the new key.
func (a *activities) SummarizeTranscript(ctx context.Context, in SummarizeInput) (SummarizeResult, error) {
	transcript, err := a.readTranscript(ctx, in.Bucket, in.TranscriptKey)
	if err != nil {
		return SummarizeResult{}, err
	}

	summary, err := a.summarize(ctx, transcript.Text)
	if err != nil {
		return SummarizeResult{}, err
	}

	summaryKey := deriveSummaryKey(in.TranscriptKey)
	body, err := json.Marshal(map[string]string{"summary": summary})
	if err != nil {
		return SummarizeResult{}, fmt.Errorf("marshal summary: %w", err)
	}
	if _, err := a.s3.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &in.Bucket,
		Key:         &summaryKey,
		Body:        bytes.NewReader(body),
		ContentType: aws.String("application/json"),
	}); err != nil {
		return SummarizeResult{}, fmt.Errorf("put summary %s: %w", summaryKey, err)
	}

	return SummarizeResult{SummaryKey: summaryKey}, nil
}

func (a *activities) readTranscript(ctx context.Context, bucket, key string) (Transcript, error) {
	obj, err := a.s3.GetObject(ctx, &s3.GetObjectInput{Bucket: &bucket, Key: &key})
	if err != nil {
		return Transcript{}, fmt.Errorf("get transcript %s: %w", key, err)
	}
	defer obj.Body.Close()

	var t Transcript
	if err := json.NewDecoder(obj.Body).Decode(&t); err != nil {
		return Transcript{}, fmt.Errorf("decode transcript %s: %w", key, err)
	}
	return t, nil
}

// ---- OpenAI Chat Completions ----

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatRequest struct {
	Model     string        `json:"model"`
	Messages  []chatMessage `json:"messages"`
	MaxTokens int           `json:"max_tokens,omitempty"`
}

type chatResponse struct {
	Choices []struct {
		Message chatMessage `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func (a *activities) summarize(ctx context.Context, transcript string) (string, error) {
	reqBody, err := json.Marshal(chatRequest{
		Model: a.model,
		Messages: []chatMessage{
			{Role: "system", Content: "You write concise, accurate meeting summaries."},
			{Role: "user", Content: "Summarize the following meeting transcript in a few concise " +
				"paragraphs. Lead with the key decisions and outcomes.\n\n" + transcript},
		},
		MaxTokens: 1024,
	})
	if err != nil {
		return "", fmt.Errorf("marshal openai request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, a.baseURL+"/chat/completions", bytes.NewReader(reqBody))
	if err != nil {
		return "", fmt.Errorf("build openai request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+a.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := a.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("openai request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read openai response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("openai status %d: %s", resp.StatusCode, string(respBody))
	}

	var cr chatResponse
	if err := json.Unmarshal(respBody, &cr); err != nil {
		return "", fmt.Errorf("decode openai response: %w", err)
	}
	if len(cr.Choices) == 0 {
		return "", fmt.Errorf("openai returned no choices: %s", string(respBody))
	}
	return cr.Choices[0].Message.Content, nil
}

// deriveSummaryKey maps transcripts/<name>.json -> summaries/<name>.summary.json.
func deriveSummaryKey(transcriptKey string) string {
	base := strings.TrimPrefix(transcriptKey, "transcripts/")
	base = strings.TrimSuffix(base, ".json")
	return "summaries/" + base + ".summary.json"
}
