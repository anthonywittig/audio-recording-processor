/*eslint-disable block-scoped-var, id-length, no-control-regex, no-magic-numbers, no-mixed-operators, no-prototype-builtins, no-redeclare, no-shadow, no-var, sort-vars, default-case, jsdoc/require-param*/
"use strict";

var $protobuf = require("protobufjs/light");

var $root = ($protobuf.roots["default"] || ($protobuf.roots["default"] = new $protobuf.Root()))
.addJSON({
  "arp": {
    "nested": {
      "v1": {
        "options": {
          "go_package": "github.com/anthonywittig/audio-recording-processor/services/summarize-go/gen/arpv1;arpv1",
          "java_package": "com.arp.proto",
          "java_multiple_files": true
        },
        "nested": {
          "ProcessAudioInput": {
            "fields": {
              "bucket": {
                "type": "string",
                "id": 1
              },
              "audioKey": {
                "type": "string",
                "id": 2,
                "protoName": "audio_key"
              },
              "recipientEmail": {
                "type": "string",
                "id": 3,
                "protoName": "recipient_email"
              }
            }
          },
          "TranscribeInput": {
            "fields": {
              "bucket": {
                "type": "string",
                "id": 1
              },
              "audioKey": {
                "type": "string",
                "id": 2,
                "protoName": "audio_key"
              }
            }
          },
          "TranscribeResult": {
            "fields": {
              "transcriptKey": {
                "type": "string",
                "id": 1,
                "protoName": "transcript_key"
              }
            }
          },
          "SummarizeInput": {
            "fields": {
              "bucket": {
                "type": "string",
                "id": 1
              },
              "transcriptKey": {
                "type": "string",
                "id": 2,
                "protoName": "transcript_key"
              }
            }
          },
          "SummarizeResult": {
            "fields": {
              "summaryKey": {
                "type": "string",
                "id": 1,
                "protoName": "summary_key"
              }
            }
          },
          "ActionItemsInput": {
            "fields": {
              "bucket": {
                "type": "string",
                "id": 1
              },
              "transcriptKey": {
                "type": "string",
                "id": 2,
                "protoName": "transcript_key"
              }
            }
          },
          "ActionItemsResult": {
            "fields": {
              "actionItemsKey": {
                "type": "string",
                "id": 1,
                "protoName": "action_items_key"
              }
            }
          },
          "EmailInput": {
            "fields": {
              "bucket": {
                "type": "string",
                "id": 1
              },
              "transcriptKey": {
                "type": "string",
                "id": 2,
                "protoName": "transcript_key"
              },
              "summaryKey": {
                "type": "string",
                "id": 3,
                "protoName": "summary_key"
              },
              "actionItemsKey": {
                "type": "string",
                "id": 4,
                "protoName": "action_items_key"
              },
              "recipientEmail": {
                "type": "string",
                "id": 5,
                "protoName": "recipient_email"
              }
            }
          },
          "EmailResult": {
            "fields": {
              "messageId": {
                "type": "string",
                "id": 1,
                "protoName": "message_id"
              }
            }
          }
        }
      }
    }
  }
});

/**
 * Reflected root namespace.
 * @type {$protobuf.Root}
 */
module.exports = $root;
