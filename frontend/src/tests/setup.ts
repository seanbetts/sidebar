import '@testing-library/jest-dom/vitest';
import { vi } from 'vitest';

if (typeof window !== 'undefined' && !window.matchMedia) {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn()
  }));
}

vi.mock('@sentry/sveltekit', () => ({
  init: vi.fn(),
  handleErrorWithSentry: () => ((input: unknown) => input),
  sentryHandle: () =>
    async ({ event, resolve }: { event: unknown; resolve: (event: unknown) => unknown }) =>
      resolve(event),
  withScope: (callback: (scope: { setContext: (name: string, context: unknown) => void }) => void) =>
    callback({ setContext: vi.fn() }),
  captureException: vi.fn(),
  captureMessage: vi.fn()
}));
