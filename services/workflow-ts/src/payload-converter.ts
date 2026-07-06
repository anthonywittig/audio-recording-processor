import { DefaultPayloadConverterWithProtobufs } from '@temporalio/common/lib/protobufs';
import type { Root } from 'protobufjs';

// root.js is a protobufjs json-module: module.exports is a real Root instance
// (which the converter requires). Non-proto values fall back to JSON, so
// unmigrated DTOs keep working during the transition.
//
// Referenced by payloadConverterPath on both the Worker and the Client so the
// same converter runs in the workflow sandbox and the main thread.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const root = require('./proto/root') as unknown as Root;

export const payloadConverter = new DefaultPayloadConverterWithProtobufs({
  protobufRoot: root as unknown as Record<string, unknown>,
});
