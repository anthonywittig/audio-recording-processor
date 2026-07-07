import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ApiError,
  clearPasscode,
  listRecordings,
  storedPasscode,
  storePasscode,
  type Recording,
} from './api';
import { Recorder } from './Recorder';
import { RecordingCard } from './RecordingCard';

const POLL_MS = 5000;

export function App() {
  const [unlocked, setUnlocked] = useState(false);
  const [gateError, setGateError] = useState<string | null>(null);
  const [recordings, setRecordings] = useState<Recording[] | null>(null);
  const [pipelineDown, setPipelineDown] = useState(false);
  const pollRef = useRef<number | undefined>(undefined);

  const refresh = useCallback(async () => {
    try {
      const res = await listRecordings();
      setRecordings(res.recordings);
      setPipelineDown(res.pipelineDown ?? false);
      setUnlocked(true);
      return res;
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        clearPasscode();
        setUnlocked(false);
        setGateError(storedPasscode() === null ? null : 'Wrong passcode.');
      }
      return null;
    }
  }, []);

  // Try the stored passcode on load.
  useEffect(() => {
    if (storedPasscode()) void refresh();
  }, [refresh]);

  // Poll while anything is still processing and the tab is visible.
  const processing = recordings?.some((r) => r.status !== 'done') ?? false;
  useEffect(() => {
    window.clearInterval(pollRef.current);
    if (!unlocked || !processing) return;
    pollRef.current = window.setInterval(() => {
      if (document.visibilityState === 'visible') void refresh();
    }, POLL_MS);
    return () => window.clearInterval(pollRef.current);
  }, [unlocked, processing, refresh]);

  // Catch up when the tab comes back to the foreground.
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState === 'visible' && unlocked) void refresh();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [unlocked, refresh]);

  async function submitPasscode(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const input = new FormData(e.currentTarget).get('passcode');
    storePasscode(String(input ?? ''));
    setGateError(null);
    const res = await refresh();
    if (!res) setGateError('Wrong passcode.');
  }

  if (!unlocked) {
    return (
      <main className="gate">
        <h1>Audio Recordings</h1>
        <form onSubmit={submitPasscode} className="card gate-form">
          <input
            name="passcode"
            type="password"
            placeholder="Passcode"
            autoFocus
            autoComplete="current-password"
          />
          <button className="primary" type="submit">
            Enter
          </button>
          {gateError && <p className="error">{gateError}</p>}
        </form>
      </main>
    );
  }

  return (
    <main>
      <h1>Audio Recordings</h1>

      {pipelineDown && (
        <p className="banner">
          The processing stack is torn down right now — recordings will queue up but nothing will
          process until it&rsquo;s back.
        </p>
      )}

      <Recorder onUploaded={() => void refresh()} />

      <section className="list">
        {recordings === null && <p className="muted">Loading…</p>}
        {recordings?.length === 0 && <p className="muted">No recordings yet.</p>}
        {recordings?.map((r) => <RecordingCard key={r.audioKey} recording={r} />)}
      </section>
    </main>
  );
}
