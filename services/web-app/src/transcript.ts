// Renders the Transcript proto-JSON with speaker attribution: anonymous
// diarization labels (spk_0, spk_1, ...) become "Speaker 1", "Speaker 2", ...
// in first-appearance order, and consecutive segments from one speaker collapse
// into a single turn. No usable segments -> callers fall back to the flat `text`.

export interface TranscriptSegment {
  speaker?: string;
  startTime?: number;
  endTime?: number;
  text?: string;
}

export interface Transcript {
  audioKey?: string;
  language?: string;
  text?: string;
  segments?: TranscriptSegment[];
}

export interface Turn {
  name: string;
  text: string;
}

export function toTurns(t: Transcript): { participants: string[]; turns: Turn[] } | null {
  const segments = (t.segments ?? []).filter((s) => (s.text ?? '').trim() !== '');
  if (segments.length === 0) return null;

  const names = new Map<string, string>();
  const turns: Turn[] = [];
  for (const seg of segments) {
    const speaker = seg.speaker ?? '';
    if (!names.has(speaker)) names.set(speaker, `Speaker ${names.size + 1}`);
    const name = names.get(speaker)!;
    const text = (seg.text ?? '').trim();

    const last = turns[turns.length - 1];
    if (last && last.name === name) last.text += ` ${text}`;
    else turns.push({ name, text });
  }

  return { participants: [...names.values()], turns };
}
