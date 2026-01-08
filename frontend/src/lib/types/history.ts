import type { Message } from './chat';

export interface Conversation {
	id: string;
	title: string;
	titleGenerated: boolean;
	createdAt: string;
	updatedAt: string;
	messageCount: number;
	firstMessage?: string;
	isArchived?: boolean;
}

export interface ConversationWithMessages extends Conversation {
	messages: Message[];
}
