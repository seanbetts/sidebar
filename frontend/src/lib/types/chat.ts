/**
 * Chat message types and SSE event types
 */

export type MessageRole = 'user' | 'assistant';

export type MessageStatus = 'pending' | 'streaming' | 'complete' | 'error';

export interface ToolCall {
	id: string;
	name: string;
	parameters: Record<string, any>;
	status: 'pending' | 'success' | 'error';
	result?: any;
}

export interface Message {
	id: string;
	role: MessageRole;
	content: string;
	status: MessageStatus;
	toolCalls?: ToolCall[];
	needsNewline?: boolean;
	timestamp: Date;
	error?: string;
}

// SSE Event types from backend
export interface TokenEvent {
	type: 'token';
	content: string;
}

export interface ToolCallEvent {
	type: 'tool_call';
	id: string;
	name: string;
	parameters: Record<string, any>;
	status: 'pending' | 'success' | 'error';
}

export interface ToolResultEvent {
	type: 'tool_result';
	id: string;
	name: string;
	result: any;
	status: 'success' | 'error';
}

export interface CompleteEvent {
	type: 'complete';
}

export interface ErrorEvent {
	type: 'error';
	error: string;
}

export type SSEEvent = TokenEvent | ToolCallEvent | ToolResultEvent | CompleteEvent | ErrorEvent;
