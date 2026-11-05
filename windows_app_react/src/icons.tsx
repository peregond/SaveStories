import type { ReactNode } from "react";

const base = { width: 20, height: 20, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.8, strokeLinecap: "round", strokeLinejoin: "round" } as const;
const make = (d: ReactNode) => (p: { size?: number }) => (
  <svg {...base} width={p.size ?? 20} height={p.size ?? 20} aria-hidden="true">{d}</svg>
);

export const IconStories = make(<><rect x="5" y="3" width="14" height="18" rx="3.5" /><circle cx="12" cy="10" r="2.6" /><path d="M8 17c.8-1.8 2.2-2.6 4-2.6s3.2.8 4 2.6" /></>);
export const IconQueue = make(<><path d="M8 6h12M8 12h12M8 18h12" /><circle cx="4" cy="6" r="1" /><circle cx="4" cy="12" r="1" /><circle cx="4" cy="18" r="1" /></>);
export const IconReels = make(<><rect x="3" y="5" width="18" height="14" rx="3.5" /><path d="m10.5 9.5 4 2.5-4 2.5z" /></>);
export const IconSettings = make(<><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" /></>);
export const IconDownload = make(<><path d="M12 4v11m0 0 4-4m-4 4-4-4" /><path d="M5 19h14" /></>);
export const IconStop = make(<rect x="6.5" y="6.5" width="11" height="11" rx="2.5" />);
export const IconFolder = make(<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H9l2 2.5h7.5A2.5 2.5 0 0 1 21 10v7.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5z" />);
export const IconBookmark = make(<path d="M7 4h10a1 1 0 0 1 1 1v15l-6-4-6 4V5a1 1 0 0 1 1-1z" />);
export const IconTrash = make(<><path d="M4 7h16M10 11v6M14 11v6" /><path d="M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3" /></>);
export const IconRefresh = make(<><path d="M20 11a8 8 0 0 0-14.5-4M4 5v4h4" /><path d="M4 13a8 8 0 0 0 14.5 4M20 19v-4h-4" /></>);
export const IconEmpty = make(<><rect x="4" y="5" width="16" height="14" rx="3" /><path d="M8 10h8M8 14h5" /></>);
export const IconArrowUp = make(<path d="M12 19V6m0 0-5 5m5-5 5 5" />);
