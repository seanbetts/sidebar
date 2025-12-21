/**
 * Conversation list store with timeline grouping
 */
import { writable, derived } from 'svelte/store';
import type { Conversation } from '$lib/types/history';
import { conversationsAPI } from '$lib/services/api';

interface ConversationListState {
  conversations: Conversation[];
  loading: boolean;
  searchQuery: string;
}

function createConversationListStore() {
  const { subscribe, set, update } = writable<ConversationListState>({
    conversations: [],
    loading: false,
    searchQuery: ''
  });

  return {
    subscribe,

    async load() {
      update(state => ({ ...state, loading: true }));
      try {
        const conversations = await conversationsAPI.list();
        update(state => ({ ...state, conversations, loading: false }));
      } catch (error) {
        console.error('Failed to load conversations:', error);
        update(state => ({ ...state, loading: false }));
      }
    },

    async refresh() {
      await this.load();
    },

    async search(query: string) {
      update(state => ({ ...state, searchQuery: query, loading: true }));
      try {
        const conversations = query
          ? await conversationsAPI.search(query)
          : await conversationsAPI.list();
        update(state => ({ ...state, conversations, loading: false }));
      } catch (error) {
        console.error('Failed to search conversations:', error);
        update(state => ({ ...state, loading: false }));
      }
    },

    async deleteConversation(id: string) {
      try {
        await conversationsAPI.delete(id);
        update(state => ({
          ...state,
          conversations: state.conversations.filter(c => c.id !== id)
        }));
      } catch (error) {
        console.error('Failed to delete conversation:', error);
      }
    }
  };
}

export const conversationListStore = createConversationListStore();

// Derived store for timeline grouping
export const groupedConversations = derived(
  conversationListStore,
  ($store) => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    const lastWeek = new Date(today);
    lastWeek.setDate(lastWeek.getDate() - 7);
    const lastMonth = new Date(today);
    lastMonth.setDate(lastMonth.getDate() - 30);

    const groups = {
      today: [] as Conversation[],
      yesterday: [] as Conversation[],
      lastWeek: [] as Conversation[],
      lastMonth: [] as Conversation[],
      older: [] as Conversation[]
    };

    $store.conversations.forEach(conv => {
      const date = new Date(conv.updatedAt);
      if (date >= today) groups.today.push(conv);
      else if (date >= yesterday) groups.yesterday.push(conv);
      else if (date >= lastWeek) groups.lastWeek.push(conv);
      else if (date >= lastMonth) groups.lastMonth.push(conv);
      else groups.older.push(conv);
    });

    return groups;
  }
);

// Track current conversation
export const currentConversationId = writable<string | null>(null);
