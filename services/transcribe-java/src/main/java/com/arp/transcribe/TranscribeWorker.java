package com.arp.transcribe;

import io.temporal.client.WorkflowClient;
import io.temporal.client.WorkflowClientOptions;
import io.temporal.serviceclient.WorkflowServiceStubs;
import io.temporal.serviceclient.WorkflowServiceStubsOptions;
import io.temporal.worker.Worker;
import io.temporal.worker.WorkerFactory;

public class TranscribeWorker {

  static final String TASK_QUEUE = "transcribe";

  public static void main(String[] args) {
    String address = getenv("TEMPORAL_ADDRESS", "localhost:7233");
    String namespace = getenv("TEMPORAL_NAMESPACE", "default");

    WorkflowServiceStubs service = WorkflowServiceStubs.newServiceStubs(
        WorkflowServiceStubsOptions.newBuilder().setTarget(address).build());
    WorkflowClient client = WorkflowClient.newInstance(service,
        WorkflowClientOptions.newBuilder().setNamespace(namespace).build());

    WorkerFactory factory = WorkerFactory.newInstance(client);
    Worker worker = factory.newWorker(TASK_QUEUE);
    worker.registerActivitiesImplementations(new TranscribeActivitiesImpl());

    System.out.printf("transcribe worker started: address=%s namespace=%s queue=%s%n",
        address, namespace, TASK_QUEUE);
    factory.start();
  }

  static String getenv(String key, String def) {
    String v = System.getenv(key);
    return (v == null || v.isEmpty()) ? def : v;
  }
}
