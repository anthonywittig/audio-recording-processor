package com.arp.transcribe.model;

// Mirrors the shape in services/workflow-ts/src/shared.ts. Jackson serializes
// record components by name, so the JSON fields are "bucket" and "audioKey".
public record TranscribeInput(String bucket, String audioKey) {}
