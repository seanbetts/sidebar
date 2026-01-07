import { browser } from '$app/environment';
import {
  PUBLIC_CHAT_METRICS_ENDPOINT,
  PUBLIC_CHAT_METRICS_SAMPLE_RATE
} from '$env/static/public';

type ChatMetricName =
  | 'first_token_latency_ms'
  | 'stream_duration_ms'
  | 'sse_connect_ms'
  | 'tool_duration_ms'
  | 'sse_error'
  | 'stream_error';

type ToolStatus = 'success' | 'error';

type StreamState = {
  startedAt: number;
  firstTokenAt?: number;
  firstEventAt?: number;
  sampled: boolean;
  toolStarts: Map<string, number>;
};

const metricsEndpoint = PUBLIC_CHAT_METRICS_ENDPOINT ?? '';
const metricsSampleRate = parseSampleRate(PUBLIC_CHAT_METRICS_SAMPLE_RATE, 1);

const streams = new Map<string, StreamState>();

function parseSampleRate(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(1, Math.max(0, parsed));
}

function shouldSample(rate: number): boolean {
  if (rate <= 0) return false;
  if (rate >= 1) return true;
  return Math.random() <= rate;
}

function reportMetric(payload: {
  name: ChatMetricName;
  value: number;
  tool_name?: string;
  status?: ToolStatus;
}): void {
  if (!browser || !metricsEndpoint) return;
  const body = JSON.stringify({
    ...payload,
    timestamp: new Date().toISOString()
  });
  if (navigator.sendBeacon) {
    navigator.sendBeacon(metricsEndpoint, body);
    return;
  }
  void fetch(metricsEndpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
    keepalive: true
  }).catch(() => undefined);
}

function getStreamState(messageId: string): StreamState | null {
  return streams.get(messageId) ?? null;
}

export function startChatStream(messageId: string): void {
  if (!browser || !metricsEndpoint) return;
  streams.set(messageId, {
    startedAt: Date.now(),
    sampled: shouldSample(metricsSampleRate),
    toolStarts: new Map()
  });
}

export function markFirstEvent(messageId: string, elapsedMs: number): void {
  const state = getStreamState(messageId);
  if (!state || state.firstEventAt) return;
  state.firstEventAt = Date.now();
  if (state.sampled) {
    reportMetric({ name: 'sse_connect_ms', value: Math.max(0, elapsedMs) });
  }
}

export function markFirstToken(messageId: string): void {
  const state = getStreamState(messageId);
  if (!state || state.firstTokenAt) return;
  const now = Date.now();
  state.firstTokenAt = now;
  if (!state.sampled) return;
  reportMetric({
    name: 'first_token_latency_ms',
    value: Math.max(0, now - state.startedAt)
  });
}

export function markStreamComplete(messageId: string): void {
  const state = getStreamState(messageId);
  if (!state) return;
  if (state.sampled) {
    reportMetric({
      name: 'stream_duration_ms',
      value: Math.max(0, Date.now() - state.startedAt)
    });
  }
  streams.delete(messageId);
}

export function markStreamError(messageId: string): void {
  const state = getStreamState(messageId);
  if (!state) return;
  if (state.sampled) {
    reportMetric({ name: 'stream_error', value: 1 });
  }
  streams.delete(messageId);
}

export function markSseError(messageId: string): void {
  const state = getStreamState(messageId);
  if (!state) return;
  if (state.sampled) {
    reportMetric({ name: 'sse_error', value: 1 });
  }
}

export function markToolStart(messageId: string, toolName: string): void {
  const state = getStreamState(messageId);
  if (!state) return;
  state.toolStarts.set(toolName, Date.now());
}

export function markToolEnd(messageId: string, toolName: string, status: ToolStatus): void {
  const state = getStreamState(messageId);
  if (!state) return;
  const startedAt = state.toolStarts.get(toolName);
  state.toolStarts.delete(toolName);
  if (!state.sampled || startedAt === undefined) return;
  reportMetric({
    name: 'tool_duration_ms',
    value: Math.max(0, Date.now() - startedAt),
    tool_name: toolName,
    status
  });
}
