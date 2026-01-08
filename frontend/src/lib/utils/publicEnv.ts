export type PublicEnv = {
	PUBLIC_ENABLE_WEB_VITALS?: string;
	PUBLIC_METRICS_ENDPOINT?: string;
	PUBLIC_WEB_VITALS_SAMPLE_RATE?: string;
	PUBLIC_CHAT_METRICS_ENDPOINT?: string;
	PUBLIC_CHAT_METRICS_SAMPLE_RATE?: string;
	PUBLIC_SENTRY_DSN_FRONTEND?: string;
	PUBLIC_SENTRY_ENVIRONMENT?: string;
	PUBLIC_SENTRY_SAMPLE_RATE?: string;
};

/**
 * Return public env values from SvelteKit or Node contexts.
 * @returns Public environment variables for metrics and telemetry.
 */
export function getPublicEnv(): PublicEnv {
	const metaEnv = typeof import.meta !== 'undefined' ? ((import.meta as ImportMeta).env ?? {}) : {};
	const processEnv = typeof process !== 'undefined' ? (process.env ?? {}) : {};

	return {
		PUBLIC_ENABLE_WEB_VITALS:
			metaEnv.PUBLIC_ENABLE_WEB_VITALS ?? processEnv.PUBLIC_ENABLE_WEB_VITALS,
		PUBLIC_METRICS_ENDPOINT: metaEnv.PUBLIC_METRICS_ENDPOINT ?? processEnv.PUBLIC_METRICS_ENDPOINT,
		PUBLIC_WEB_VITALS_SAMPLE_RATE:
			metaEnv.PUBLIC_WEB_VITALS_SAMPLE_RATE ?? processEnv.PUBLIC_WEB_VITALS_SAMPLE_RATE,
		PUBLIC_CHAT_METRICS_ENDPOINT:
			metaEnv.PUBLIC_CHAT_METRICS_ENDPOINT ?? processEnv.PUBLIC_CHAT_METRICS_ENDPOINT,
		PUBLIC_CHAT_METRICS_SAMPLE_RATE:
			metaEnv.PUBLIC_CHAT_METRICS_SAMPLE_RATE ?? processEnv.PUBLIC_CHAT_METRICS_SAMPLE_RATE,
		PUBLIC_SENTRY_DSN_FRONTEND:
			metaEnv.PUBLIC_SENTRY_DSN_FRONTEND ?? processEnv.PUBLIC_SENTRY_DSN_FRONTEND,
		PUBLIC_SENTRY_ENVIRONMENT:
			metaEnv.PUBLIC_SENTRY_ENVIRONMENT ?? processEnv.PUBLIC_SENTRY_ENVIRONMENT,
		PUBLIC_SENTRY_SAMPLE_RATE:
			metaEnv.PUBLIC_SENTRY_SAMPLE_RATE ?? processEnv.PUBLIC_SENTRY_SAMPLE_RATE
	};
}
