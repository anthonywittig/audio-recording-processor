package com.arp.transcribe.model;

public record TranscriptSegment(
    String speaker,
    double startTime,
    double endTime,
    String text) {}
