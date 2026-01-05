import '@testing-library/jest-dom/vitest';
import { vi } from 'vitest';

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
