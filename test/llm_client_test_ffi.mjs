let streamDeltas = 0;

export function resetStreamDeltas() {
  streamDeltas = 0;
  return undefined;
}

export function recordStreamDelta(_delta) {
  streamDeltas += 1;
  return undefined;
}

export function streamDeltaCount() {
  return streamDeltas;
}
