import { get } from 'svelte/store';
import { conversationListStore } from '$lib/stores/conversations';
import { handleFetchError, logError } from '$lib/utils/errorHandling';

const inFlight = new Set<string>();

/**
 * Trigger title generation for a conversation.
 *
 * @param conversationId - Conversation ID to update.
 * @throws Error when the API request fails.
 */
export async function generateConversationTitle(conversationId: string): Promise<void> {
  const state = get(conversationListStore);
  const conversation = state.conversations.find(item => item.id === conversationId);
  if (conversation?.titleGenerated || inFlight.has(conversationId)) {
    return;
  }

  inFlight.add(conversationId);
  conversationListStore.setGeneratingTitle(conversationId, true);

  try {
    const response = await fetch('/api/v1/chat/generate-title', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ conversation_id: conversationId })
    });

    if (!response.ok) {
      await handleFetchError(response);
    }

    const data = await response.json();
    conversationListStore.updateConversationTitle(conversationId, data.title, !data.fallback);
  } catch (error) {
    logError('Title generation error', error, { conversationId });
    conversationListStore.setGeneratingTitle(conversationId, false);
  } finally {
    inFlight.delete(conversationId);
  }
}
