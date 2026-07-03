package com.arp.transcribe.model;

import java.util.List;

// The normalized transcript written to S3 and consumed by the Go (summarize)
// and Python (action-items) workers. Keep field names in sync across languages.
public record Transcript(
    String audioKey,
    String language,
    String text,
    List<TranscriptSegment> segments) {}
