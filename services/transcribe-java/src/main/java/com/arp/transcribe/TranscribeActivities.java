package com.arp.transcribe;

import com.arp.proto.TranscribeInput;
import com.arp.proto.TranscribeResult;
import io.temporal.activity.ActivityInterface;
import io.temporal.activity.ActivityMethod;

@ActivityInterface
public interface TranscribeActivities {

  // The Java SDK defaults activity type names to PascalCase ("TranscribeAudio"),
  // but the TS workflow calls "transcribeAudio". Override to match exactly, or
  // the workflow's activity task would never be picked up.
  @ActivityMethod(name = "transcribeAudio")
  TranscribeResult transcribeAudio(TranscribeInput input);
}
