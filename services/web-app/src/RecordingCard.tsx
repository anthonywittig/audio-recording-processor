import { useEffect, useState } from 'react';
import type { Recording } from './api';
import { toTurns, type Transcript } from './transcript';

interface Artifacts {
  transcript?: Transcript;
  summary?: string;
  actionItems?: string[];
}

const STATUS_LABEL: Record<Recording['status'], string> = {
  transcribing: 'Transcribing…',
  analyzing: 'Summarizing…',
  done: 'Done',
};

export function RecordingCard({ recording }: { recording: Recording }) {
  const [open, setOpen] = useState(false);
  const [artifacts, setArtifacts] = useState<Artifacts | null>(null);
  const [error, setError] = useState<string | null>(null);

  // (Re)fetch artifacts when opened and whenever more of them exist. The
  // presigned URLs change on every list refresh, so key off which artifacts
  // exist rather than the URLs themselves.
  const availability = `${!!recording.urls.transcript}-${!!recording.urls.summary}-${!!recording.urls.actionItems}`;
  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    (async () => {
      try {
        const { urls } = recording;
        const [transcript, summary, actionItems] = await Promise.all([
          urls.transcript ? (await fetch(urls.transcript)).json() : undefined,
          urls.summary ? (await fetch(urls.summary)).json() : undefined,
          urls.actionItems ? (await fetch(urls.actionItems)).json() : undefined,
        ]);
        if (cancelled) return;
        setArtifacts({
          transcript,
          summary: summary?.summary,
          actionItems: actionItems?.actionItems,
        });
      } catch {
        if (!cancelled) setError('Could not load results (links may have expired — refresh).');
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, availability]);

  const when = recording.lastModified
    ? new Date(recording.lastModified).toLocaleString()
    : recording.name;
  const diarized = artifacts?.transcript ? toTurns(artifacts.transcript) : null;

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

          {artifacts?.summary && (
            <>
              <h3>Summary</h3>
              <p className="prewrap">{artifacts.summary}</p>
            </>
          )}

          {artifacts?.actionItems && artifacts.actionItems.length > 0 && (
            <>
              <h3>Action items</h3>
              <ul>
                {artifacts.actionItems.map((item, i) => (
                  <li key={i}>{item}</li>
                ))}
              </ul>
            </>
          )}

          {artifacts?.transcript && (
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
                <p className="prewrap">{artifacts.transcript.text}</p>
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
