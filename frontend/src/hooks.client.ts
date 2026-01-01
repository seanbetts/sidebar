import type { HandleFetch } from '@sveltejs/kit';
import { goto, invalidateAll } from '$app/navigation';
import { getSupabaseClient } from '$lib/supabase';

let handlingUnauthorized = false;

export const handleFetch: HandleFetch = async ({ request, fetch }) => {
  const response = await fetch(request);

  if (response.status === 401 && !handlingUnauthorized) {
    try {
      const url = new URL(request.url);
      if (url.pathname.startsWith('/api/')) {
        handlingUnauthorized = true;
        try {
          const supabase = getSupabaseClient();
          await supabase.auth.signOut();
        } catch {
          // Ignore if the client is not initialized.
        }
        await invalidateAll();
        await goto('/auth/login?reason=session_expired');
      }
    } finally {
      handlingUnauthorized = false;
    }
  }

  return response;
};
