/**
 * Prompt preview payload types from the Generate Prompts tool event.
 */

export interface PromptPreviewSection {
	id: string;
	title: string;
	source: string;
	chars: number;
	content?: string;
}

export interface PromptPreviewReportDocument {
	total_chars: number;
	max_chars: number;
	truncated: boolean;
	sections: PromptPreviewSection[];
}

export interface PromptPreviewReport {
	system_prompt?: PromptPreviewReportDocument;
	first_message_prompt?: PromptPreviewReportDocument;
}

export interface PromptPreviewPayload {
	system_prompt?: string | null;
	first_message_prompt?: string | null;
	system_prompt_sections?: PromptPreviewSection[];
	first_message_prompt_sections?: PromptPreviewSection[];
	prompt_report?: PromptPreviewReport;
}
