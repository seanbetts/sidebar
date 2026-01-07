import { browser } from '$app/environment';
import type { Metric } from 'web-vitals';
import { getPublicEnv } from '$lib/utils/publicEnv';

export interface PerformanceMetric {
  name: 'CLS' | 'FCP' | 'INP' | 'LCP' | 'TTFB';
  value: number;
  rating: 'good' | 'needs-improvement' | 'poor';
  route: string;
  timestamp: string;
}

type RouteGetter = () => string;

const publicEnv = getPublicEnv();
const metricsEnabled = publicEnv.PUBLIC_ENABLE_WEB_VITALS === 'true';
const metricsEndpoint = publicEnv.PUBLIC_METRICS_ENDPOINT ?? '';
const metricsSampleRate = parseSampleRate(publicEnv.PUBLIC_WEB_VITALS_SAMPLE_RATE, 1);

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

function normalizeRating(metric: Metric): PerformanceMetric['rating'] {
  if (metric.rating === 'good' || metric.rating === 'needs-improvement' || metric.rating === 'poor') {
    return metric.rating;
  }
  return 'good';
}

function toPerformanceMetric(metric: Metric, route: string): PerformanceMetric {
  return {
    name: metric.name as PerformanceMetric['name'],
    value: metric.value,
    rating: normalizeRating(metric),
    route,
    timestamp: new Date().toISOString()
  };
}

/**
 * Report a single performance metric to the configured endpoint.
 *
 * @param metric Web Vitals metric payload.
 */
export function reportMetric(metric: PerformanceMetric): void {
  if (!browser || !metricsEndpoint) return;
  const payload = JSON.stringify(metric);
  if (navigator.sendBeacon) {
    navigator.sendBeacon(metricsEndpoint, payload);
    return;
  }
  void fetch(metricsEndpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: payload,
    keepalive: true
  }).catch(() => undefined);
}

/**
 * Initialize Web Vitals tracking for the current route.
 *
 * @param getRoute Optional route getter for associating metrics with paths.
 */
export async function initWebVitals(getRoute?: RouteGetter): Promise<void> {
  if (!browser || !metricsEnabled || !shouldSample(metricsSampleRate)) return;

  const routeGetter = getRoute ?? (() => window.location.pathname);
  const handler = (metric: Metric) => {
    reportMetric(toPerformanceMetric(metric, routeGetter()));
  };

  let vitalsModule: typeof import('web-vitals');
  try {
    vitalsModule = await import('web-vitals');
  } catch {
    return;
  }
  const { onCLS, onFCP, onINP, onLCP, onTTFB } = vitalsModule;
  onCLS(handler);
  onFCP(handler);
  onINP(handler);
  onLCP(handler);
  onTTFB(handler);
}
