import { render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import PromptPreviewBanner from '$lib/components/chat/PromptPreviewBanner.svelte';

describe('PromptPreviewBanner', () => {
	it('renders prompt diagnostics summary and section pills', () => {
		render(PromptPreviewBanner, {
			systemPrompt: 'system prompt text',
			firstMessagePrompt: 'first message prompt text',
			systemPromptSections: [
				{ id: 'message_context', title: 'Message Context', source: 'system', chars: 2335 }
			],
			firstMessagePromptSections: [
				{ id: 'first_message', title: 'First Message', source: 'first', chars: 1137 }
			],
			promptReport: {
				system_prompt: {
					total_chars: 3690,
					max_chars: 40000,
					truncated: false,
					sections: [
						{ id: 'message_context', title: 'Message Context', source: 'system', chars: 2335 }
					]
				},
				first_message_prompt: {
					total_chars: 1137,
					max_chars: 8000,
					truncated: false,
					sections: [{ id: 'first_message', title: 'First Message', source: 'first', chars: 1137 }]
				}
			}
		});

		expect(screen.getByText('Prompt Preview')).toBeInTheDocument();
		expect(screen.getByText('System: 3690/40000 chars')).toBeInTheDocument();
		expect(screen.getByText('First: 1137/8000 chars')).toBeInTheDocument();
		expect(screen.getByText('message_context (2335)')).toBeInTheDocument();
		expect(screen.getByText('first_message (1137)')).toBeInTheDocument();
		expect(screen.getByText('System prompt text')).toBeInTheDocument();
		expect(screen.getByText('First message prompt text')).toBeInTheDocument();
	});
});
