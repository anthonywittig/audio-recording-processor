import { useEffect, useRef, useState } from 'react';
import { uploadRecording } from './api';

// Safari records audio/mp4 (AAC), Chrome/Firefox webm/opus — both are formats
// AWS Transcribe accepts, and the API picks the S3 key extension from the type.
function pickMimeType(): string | undefined {
  const candidates = ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm'];
  return candidates.find((c) => MediaRecorder.isTypeSupported(c));
}

type Phase = 'idle' | 'recording' | 'recorded' | 'uploading';

export function Recorder({ onUploaded }: { onUploaded: () => void }) {
  const [phase, setPhase] = useState<Phase>('idle');
  const [seconds, setSeconds] = useState(0);
  const [blob, setBlob] = useState<Blob | null>(null);
  const [error, setError] = useState<string | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<BlobPart[]>([]);
  const previewUrlRef = useRef<string | null>(null);

  useEffect(() => {
    if (phase !== 'recording') return;
    const t = setInterval(() => setSeconds((s) => s + 1), 1000);
    return () => clearInterval(t);
  }, [phase]);

  // One preview object URL per blob; revoke the previous one.
  const previewUrl = (() => {
    if (!blob) return null;
    if (previewUrlRef.current) URL.revokeObjectURL(previewUrlRef.current);
    previewUrlRef.current = URL.createObjectURL(blob);
    return previewUrlRef.current;
  })();

  async function start() {
    setError(null);
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch {
      setError('Microphone access was denied.');
      return;
    }
    const recorder = new MediaRecorder(stream, { mimeType: pickMimeType() });
    chunksRef.current = [];
    recorder.ondataavailable = (e) => {
      if (e.data.size > 0) chunksRef.current.push(e.data);
    };
    recorder.onstop = () => {
      stream.getTracks().forEach((t) => t.stop());
      setBlob(new Blob(chunksRef.current, { type: recorder.mimeType }));
      setPhase('recorded');
    };
    recorderRef.current = recorder;
    recorder.start();
    setSeconds(0);
    setPhase('recording');
  }

  function stop() {
    recorderRef.current?.stop();
  }

  function discard() {
    setBlob(null);
    setPhase('idle');
  }

  async function upload() {
    if (!blob) return;
    setPhase('uploading');
    setError(null);
    try {
      await uploadRecording(blob);
      setBlob(null);
      setPhase('idle');
      onUploaded();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed.');
      setPhase('recorded');
    }
  }

  const mm = String(Math.floor(seconds / 60)).padStart(2, '0');
  const ss = String(seconds % 60).padStart(2, '0');

  return (
    <section className="recorder card">
      {phase === 'idle' && (
        <button className="record-btn" onClick={start}>
          ● Record
        </button>
      )}

      {phase === 'recording' && (
        <div className="recording-row">
          <span className="pulse" aria-hidden>
            ●
          </span>
          <span className="timer">
            {mm}:{ss}
          </span>
          <button className="stop-btn" onClick={stop}>
            ■ Stop
          </button>
        </div>
      )}

      {(phase === 'recorded' || phase === 'uploading') && blob && (
        <div className="recorded-row">
          {previewUrl && <audio controls src={previewUrl} />}
          <div className="recorded-actions">
            <button className="primary" onClick={upload} disabled={phase === 'uploading'}>
              {phase === 'uploading' ? 'Uploading…' : 'Upload'}
            </button>
            <button onClick={discard} disabled={phase === 'uploading'}>
              Discard
            </button>
          </div>
        </div>
      )}

      {error && <p className="error">{error}</p>}
    </section>
  );
}
