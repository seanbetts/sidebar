type ForegroundMutationRetryOptions = {
	maxAttempts?: number;
	initialDelayMs?: number;
	maxDelayMs?: number;
	jitterRatio?: number;
};

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

const getErrorStatus = (error: unknown): number | null => {
	if (!error || typeof error !== 'object') return null;
	const status = (error as { status?: unknown }).status;
	return typeof status === 'number' ? status : null;
};

export function isRetryableForegroundMutationError(error: unknown): boolean {
	if (error instanceof DOMException && error.name === 'AbortError') {
		return false;
	}

	const status = getErrorStatus(error);
	if (status === null) {
		return true;
	}

	if (status === 408 || status === 425 || status === 429) {
		return true;
	}

	return status >= 500;
}

export async function retryForegroundMutation<T>(
	operation: () => Promise<T>,
	options: ForegroundMutationRetryOptions = {}
): Promise<T> {
	const maxAttempts = options.maxAttempts ?? 2;
	const initialDelayMs = options.initialDelayMs ?? 1_000;
	const maxDelayMs = options.maxDelayMs ?? 8_000;
	const jitterRatio = options.jitterRatio ?? 0.2;

	let attempt = 0;

	while (true) {
		try {
			return await operation();
		} catch (error) {
			attempt += 1;
			if (attempt >= maxAttempts || !isRetryableForegroundMutationError(error)) {
				throw error;
			}

			const baseDelay = Math.min(initialDelayMs * 2 ** (attempt - 1), maxDelayMs);
			const jitter = baseDelay * jitterRatio * Math.random();
			await sleep(baseDelay + jitter);
		}
	}
}
