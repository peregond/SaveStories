import { useEffect, useMemo, useState } from "react";
import { createMockBridge, DEFAULT_DIR, type BatchEntry, type BrowserMode, type MediaFilter } from "./bridge";

export function useRunner() {
  const bridge = useMemo(() => createMockBridge(), []);
  const [entries, setEntries] = useState<BatchEntry[]>([]);
  const [log, setLog] = useState<string[]>([]);
  const [step, setStep] = useState("Ожидание команды.");
  const [running, setRunning] = useState(false);
  const [browser, setBrowser] = useState<BrowserMode>("background");
  const [media, setMedia] = useState<MediaFilter>("all");
  const [directory, setDirectory] = useState(DEFAULT_DIR);

  useEffect(() => bridge.onUpdate((e, l, s) => {
    setEntries(e); setLog(l); setStep(s);
    setRunning(e.some((x) => x.status === "pending" || x.status === "running"));
  }), [bridge]);

  const start = (urls: string[]) => {
    if (!urls.length) return;
    setRunning(true);
    void bridge.startBatch({ urls, outputDirectory: directory, headless: browser === "background", mediaFilter: media });
  };
  const stop = () => { bridge.stop(); setRunning(false); setStep("Остановлено."); };
  const pick = async () => { const d = await bridge.pickDirectory(); if (d) setDirectory(d); };
  const clear = () => { setEntries([]); setLog([]); setStep("Ожидание команды."); };

  const done = entries.filter((e) => e.status === "done").length;
  const stats = {
    profiles: entries.length,
    saved: entries.reduce((n, e) => n + (e.saved ?? 0), 0),
    files: entries.reduce((n, e) => n + (e.found ?? 0), 0),
    folders: done,
  };
  const progress = entries.length ? Math.round((done / entries.length) * 100) : 0;
  return { entries, log, step, running, stats, progress, browser, setBrowser, media, setMedia, directory, pick, start, stop, clear };
}
export type Runner = ReturnType<typeof useRunner>;
