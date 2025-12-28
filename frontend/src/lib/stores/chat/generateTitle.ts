import { conversationListStore } from '$lib/stores/conversations';

export async function generateConversationTitle(conversationId: string): Promise<void> {
  conversationListStore.setGeneratingTitle(conversationId, true);

  try {
    const response = await fetch('/api/chat/generate-title', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ conversation_id: conversationId })
    });

    if (!response.ok) {
      throw new Error(`Failed to generate title: ${response.statusText}`);
    }

    const data = await response.json();
    console.log(`Title generated: ${data.title}${data.fallback ? ' (fallback)' : ''}`);

    conversationListStore.updateConversationTitle(conversationId, data.title);
  } catch (error) {
    console.error('Title generation error:', error);
    conversationListStore.setGeneratingTitle(conversationId, false);
  }
}
