import { useEffect, useState } from 'react';
import type { Recording } from './api';
import { toTurns, type Bundle } from './transcript';

const STATUS_LABEL: Record<Recording['status'], string> = {
  transcribing: 'Transcribing…',
  analyzing: 'Summarizing…',
  done: 'Done',
};

export function RecordingCard({ recording }: { recording: Recording }) {
  const [open, setOpen] = useState(false);
  const [bundle, setBundle] = useState<Bundle | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Fetch the bundle when opened and once it exists. The presigned URL changes
  // on every list refresh, so key off its existence rather than its value.
  const hasBundle = !!recording.urls.bundle;
  useEffect(() => {
    if (!open || !recording.urls.bundle) return;
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(recording.urls.bundle!);
        if (!res.ok) throw new Error(`bundle fetch ${res.status}`);
        const data = (await res.json()) as Bundle;
        if (!cancelled) setBundle(data);
      } catch {
        if (!cancelled) setError('Could not load results (links may have expired — refresh).');
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, hasBundle]);

  const when = recording.lastModified
    ? new Date(recording.lastModified).toLocaleString()
    : recording.name;
  const diarized = bundle?.transcript ? toTurns(bundle.transcript) : null;
  const actionItems = bundle?.actionItems?.actionItems ?? [];

  return (
    <article className={`card recording ${open ? 'open' : ''}`}>
      <button className="recording-header" onClick={() => setOpen((o) => !o)}>
        <span className="recording-when">{when}</span>
        <span className={`status status-${recording.status}`}>{STATUS_LABEL[recording.status]}</span>
      </button>

      {open && (
        <div className="recording-body">
          <audio controls preload="none" src={recording.urls.audio} />
          {error && <p className="error">{error}</p>}

          {bundle?.summary?.summary && (
            <>
              <h3>Summary</h3>
              <p className="prewrap">{bundle.summary.summary}</p>
            </>
          )}

          {actionItems.length > 0 && (
            <>
              <h3>Action items</h3>
              <ul>
                {actionItems.map((item, i) => (
                  <li key={i}>{item}</li>
                ))}
              </ul>
            </>
          )}

          {bundle?.transcript && (
            <>
              <h3>Transcript</h3>
              {diarized ? (
                <>
                  <p className="participants">Participants: {diarized.participants.join(', ')}</p>
                  {diarized.turns.map((turn, i) => (
                    <p key={i} className="turn">
                      <strong>{turn.name}:</strong> {turn.text}
                    </p>
                  ))}
                </>
              ) : (
                <p className="prewrap">{bundle.transcript.text}</p>
              )}
            </>
          )}

          {recording.status !== 'done' && !error && (
            <p className="muted">Still processing — this refreshes automatically.</p>
          )}
        </div>
      )}
    </article>
  );
}
