import { DefaultPayloadConverterWithProtobufs } from '@temporalio/common/lib/protobufs';
import type { Root } from 'protobufjs';

// root.js is a protobufjs json-module: module.exports is a real Root instance.
// Referenced by the Client's payloadConverterPath so the ProcessAudioInput we
// start workflows with is encoded as a protobuf payload.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const root = require('./proto/root') as unknown as Root;

export const payloadConverter = new DefaultPayloadConverterWithProtobufs({
  protobufRoot: root as unknown as Record<string, unknown>,
});
