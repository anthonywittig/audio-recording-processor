package com.arp.transcribe;

import com.arp.transcribe.model.TranscribeInput;
import com.arp.transcribe.model.TranscribeResult;
import com.arp.transcribe.model.Transcript;
import com.arp.transcribe.model.TranscriptSegment;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.temporal.activity.Activity;
import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.transcribe.TranscribeClient;
import software.amazon.awssdk.services.transcribe.model.GetTranscriptionJobRequest;
import software.amazon.awssdk.services.transcribe.model.Media;
import software.amazon.awssdk.services.transcribe.model.Settings;
import software.amazon.awssdk.services.transcribe.model.StartTranscriptionJobRequest;
import software.amazon.awssdk.services.transcribe.model.TranscriptionJob;
import software.amazon.awssdk.services.transcribe.model.TranscriptionJobStatus;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

public class TranscribeActivitiesImpl implements TranscribeActivities {

  private static final int MAX_SPEAKERS = 10;
  private static final long POLL_INTERVAL_MS = 15_000;

  private final S3Client s3 = S3Client.create();
  private final TranscribeClient transcribe = TranscribeClient.create();
  private final ObjectMapper mapper = new ObjectMapper();

  @Override
  public TranscribeResult transcribeAudio(TranscribeInput input) {
    String jobName = "arp-" + UUID.randomUUID();
    String mediaUri = "s3://" + input.bucket() + "/" + input.audioKey();
    String rawOutputKey = "transcribe-raw/" + jobName + ".json";

    transcribe.startTranscriptionJob(StartTranscriptionJobRequest.builder()
        .transcriptionJobName(jobName)
        .languageCode("en-US")
        .mediaFormat(mediaFormatFor(input.audioKey()))
        .media(Media.builder().mediaFileUri(mediaUri).build())
        .outputBucketName(input.bucket())
        .outputKey(rawOutputKey)
        .settings(Settings.builder()
            .showSpeakerLabels(true)
            .maxSpeakerLabels(MAX_SPEAKERS)
            .build())
        .build());

    // Poll until the async job finishes, heartbeating so Temporal knows the
    // activity is still alive (heartbeatTimeout is set on the workflow side).
    TranscriptionJob job;
    while (true) {
      job = transcribe.getTranscriptionJob(GetTranscriptionJobRequest.builder()
          .transcriptionJobName(jobName).build()).transcriptionJob();
      TranscriptionJobStatus status = job.transcriptionJobStatus();
      Activity.getExecutionContext().heartbeat("status=" + status);

      if (status == TranscriptionJobStatus.COMPLETED) {
        break;
      }
      if (status == TranscriptionJobStatus.FAILED) {
        throw Activity.wrap(new RuntimeException("transcription failed: " + job.failureReason()));
      }
      sleep(POLL_INTERVAL_MS);
    }

    try {
      JsonNode raw = readJson(input.bucket(), rawOutputKey);
      Transcript transcript = flatten(input, raw);
      String transcriptKey = deriveTranscriptKey(input.audioKey());
      putJson(input.bucket(), transcriptKey, transcript);
      return new TranscribeResult(transcriptKey);
    } catch (Exception e) {
      throw Activity.wrap(e);
    }
  }

  // flatten converts AWS Transcribe's native output (full text + speaker_labels
  // segments + timestamped items) into our normalized Transcript. Per-speaker
  // text is reconstructed by joining the words whose start times fall in each
  // speaker segment.
  private Transcript flatten(TranscribeInput input, JsonNode root) {
    JsonNode results = root.path("results");
    String text = results.path("transcripts").path(0).path("transcript").asText("");

    Map<String, String> wordByStart = new HashMap<>();
    for (JsonNode item : results.path("items")) {
      if ("pronunciation".equals(item.path("type").asText())) {
        wordByStart.put(
            item.path("start_time").asText(),
            item.path("alternatives").path(0).path("content").asText());
      }
    }

    List<TranscriptSegment> segments = new ArrayList<>();
    for (JsonNode seg : results.path("speaker_labels").path("segments")) {
      String speaker = seg.path("speaker_label").asText();
      double start = seg.path("start_time").asDouble();
      double end = seg.path("end_time").asDouble();

      StringBuilder sb = new StringBuilder();
      for (JsonNode segItem : seg.path("items")) {
        String word = wordByStart.get(segItem.path("start_time").asText());
        if (word != null) {
          if (sb.length() > 0) {
            sb.append(' ');
          }
          sb.append(word);
        }
      }
      segments.add(new TranscriptSegment(speaker, start, end, sb.toString()));
    }

    return new Transcript(input.audioKey(), "en-US", text, segments);
  }

  private JsonNode readJson(String bucket, String key) throws Exception {
    ResponseBytes<GetObjectResponse> bytes = s3.getObjectAsBytes(
        GetObjectRequest.builder().bucket(bucket).key(key).build());
    return mapper.readTree(bytes.asByteArray());
  }

  private void putJson(String bucket, String key, Object value) throws Exception {
    byte[] data = mapper.writeValueAsBytes(value);
    s3.putObject(
        PutObjectRequest.builder().bucket(bucket).key(key).contentType("application/json").build(),
        RequestBody.fromBytes(data));
  }

  // deriveTranscriptKey maps audio/<name> -> transcripts/<name>.json.
  private static String deriveTranscriptKey(String audioKey) {
    String base = audioKey.startsWith("audio/") ? audioKey.substring("audio/".length()) : audioKey;
    return "transcripts/" + base + ".json";
  }

  private static String mediaFormatFor(String audioKey) {
    String lower = audioKey.toLowerCase();
    int dot = lower.lastIndexOf('.');
    String ext = dot >= 0 ? lower.substring(dot + 1) : "";
    return switch (ext) {
      case "mp4", "m4a" -> "mp4";
      case "wav" -> "wav";
      case "flac" -> "flac";
      case "ogg" -> "ogg";
      case "amr" -> "amr";
      case "webm" -> "webm";
      default -> "mp3";
    };
  }

  private static void sleep(long ms) {
    try {
      Thread.sleep(ms);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new RuntimeException(e);
    }
  }
}
