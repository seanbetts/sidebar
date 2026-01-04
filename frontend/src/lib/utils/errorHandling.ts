export interface StructuredError {
  message: string;
  status: number;
  code?: string;
  context?: Record<string, unknown>;
}

export class APIError extends Error {
  status: number;
  code?: string;
  context?: Record<string, unknown>;

  constructor(error: StructuredError) {
    super(error.message);
    this.name = 'APIError';
    this.status = error.status;
    this.code = error.code;
    this.context = error.context;
  }
}

/**
 * Log errors with structured context for debugging.
 */
export function logError(
  message: string,
  error: unknown,
  context?: Record<string, unknown>
): void {
  console.error(message, {
    error: error instanceof Error
      ? { name: error.name, message: error.message, stack: error.stack }
      : error,
    context,
    timestamp: new Date().toISOString()
  });
}

/**
 * Normalize errors into structured payloads.
 */
export function parseError(error: unknown): StructuredError {
  if (error instanceof APIError) {
    return {
      message: error.message,
      status: error.status,
      code: error.code,
      context: error.context
    };
  }

  if (error instanceof Error) {
    return {
      message: error.message,
      status: 500
    };
  }

  return {
    message: 'An unexpected error occurred',
    status: 500
  };
}

/**
 * Throw a structured APIError based on a failed fetch response.
 */
export async function handleFetchError(response: Response): Promise<never> {
  const errorData = await response.json().catch(() => ({
    error: response.statusText
  }));

  throw new APIError({
    message: errorData.error || errorData.message || 'Request failed',
    status: response.status,
    code: errorData.code,
    context: errorData.context
  });
}
