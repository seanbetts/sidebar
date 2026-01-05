import { browser } from '$app/environment';
import {
  PUBLIC_SENTRY_DSN_FRONTEND,
  PUBLIC_SENTRY_ENVIRONMENT,
  PUBLIC_SENTRY_SAMPLE_RATE
} from '$env/static/public';
import type { Event as SentryEvent } from '@sentry/core';
import * as Sentry from '@sentry/sveltekit';

type SentryContext = Record<string, unknown>;

const sentryDsn = PUBLIC_SENTRY_DSN_FRONTEND ?? '';
const sentryEnvironment = PUBLIC_SENTRY_ENVIRONMENT || 'production';
const sentrySampleRate = parseSampleRate(PUBLIC_SENTRY_SAMPLE_RATE, 1);

let sentryInitialized = false;

function parseSampleRate(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(1, Math.max(0, parsed));
}

function sanitizeEvent(event: SentryEvent): SentryEvent {
  if (!event.request?.headers || typeof event.request.headers !== 'object') {
    return event;
  }

  const headers = { ...event.request.headers } as Record<string, unknown>;
  delete headers.authorization;
  delete headers.cookie;

  return {
    ...event,
    request: {
      ...event.request,
      headers
    }
  };
}

function initSentrySdk(): void {
  if (sentryInitialized || !sentryDsn) return;

  Sentry.init({
    dsn: sentryDsn,
    environment: sentryEnvironment,
    sampleRate: sentrySampleRate,
    tracesSampleRate: sentrySampleRate,
    beforeSend: sanitizeEvent
  });

  sentryInitialized = true;
}

/**
 * Initialize Sentry for browser execution.
 */
export function initSentryClient(): void {
  if (!browser) return;
  initSentrySdk();
}

/**
 * Initialize Sentry for server execution.
 */
export function initSentryServer(): void {
  if (browser) return;
  initSentrySdk();
}

/**
 * Capture an error in Sentry when configured.
 *
 * @param error Error instance or payload.
 * @param context Extra context to attach.
 */
export function captureError(error: unknown, context?: SentryContext): void {
  if (!sentryInitialized) return;

  Sentry.withScope(scope => {
    if (context) {
      scope.setContext('context', context);
    }

    if (error instanceof Error) {
      Sentry.captureException(error);
    } else {
      Sentry.captureMessage(String(error));
    }
  });
}
