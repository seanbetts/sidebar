import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';
import { chatStore } from '$lib/stores/chat';

const { conversationsAPI, conversationListStore, currentConversationId } = vi.hoisted(() => {
  const createStore = <T>(initial: T) => {
    let value = initial;
    const subscribers = new Set<(next: T) => void>();
    return {
      subscribe(run: (next: T) => void) {
        run(value);
        subscribers.add(run);
        return () => subscribers.delete(run);
      },
      set(next: T) {
        value = next;
        subscribers.forEach((fn) => fn(value));
      },
      update(updater: (current: T) => T) {
        value = updater(value);
        subscribers.forEach((fn) => fn(value));
      }
    };
  };
  return {
    conversationsAPI: {
      create: vi.fn(),
      get: vi.fn(),
      addMessage: vi.fn()
    },
    conversationListStore: {
      addConversation: vi.fn(),
      deleteConversation: vi.fn(),
      setGeneratingTitle: vi.fn(),
      updateConversationMetadata: vi.fn(),
      updateConversationTitle: vi.fn()
    },
    currentConversationId: createStore<string | null>(null)
  };
});

vi.mock('$lib/services/api', () => ({
  conversationsAPI,
  ingestionAPI: {
    get: vi.fn()
  }
}));

vi.mock('$lib/stores/conversations', () => ({
  conversationListStore,
  currentConversationId
}));

vi.mock('$lib/stores/chat/toolState', () => ({
  createToolStateHandlers: () => ({
    clearToolTimers: vi.fn(),
    setActiveTool: vi.fn(),
    finalizeActiveTool: vi.fn(),
    markNeedsNewline: vi.fn(),
    getActiveToolStartTime: vi.fn(() => null)
  })
}));

vi.mock('$lib/stores/chat/generateTitle', () => ({
  generateConversationTitle: vi.fn()
}));

vi.mock('$lib/stores/ingestion', () => ({
  ingestionStore: {
    upsertItem: vi.fn()
  }
}));

describe('chatStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    chatStore.reset();
  });

  it('starts a new conversation and updates list store', async () => {
    conversationsAPI.create.mockResolvedValue({
      id: 'conv-1',
      title: 'New',
      titleGenerated: false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      messageCount: 0
    });

    const id = await chatStore.startNewConversation();

    expect(id).toBe('conv-1');
    expect(get(currentConversationId)).toBe('conv-1');
    expect(conversationListStore.addConversation).toHaveBeenCalled();
    expect(conversationListStore.setGeneratingTitle).toHaveBeenCalledWith('conv-1', true);
  });

  it('adds user + assistant messages when sending', async () => {
    conversationsAPI.create.mockResolvedValue({
      id: 'conv-2',
      title: 'New',
      titleGenerated: false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      messageCount: 0
    });
    conversationsAPI.addMessage.mockResolvedValue({});

    const { assistantMessageId, userMessageId } = await chatStore.sendMessage('Hello');

    const state = get(chatStore);
    expect(state.messages).toHaveLength(2);
    expect(state.isStreaming).toBe(true);
    expect(state.currentMessageId).toBe(assistantMessageId);
    expect(state.messages[0].id).toBe(userMessageId);
    expect(conversationsAPI.addMessage).toHaveBeenCalled();
  });
});
