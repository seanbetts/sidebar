import { onDestroy, onMount } from 'svelte';
import { writable } from 'svelte/store';
import { thingsAPI } from '$lib/services/api';
import { logError } from '$lib/utils/errorHandling';

type ThingsStatusState = {
  status: 'loading' | 'online' | 'offline';
  deviceName: string;
  lastSeenAt: string | null;
};

const refreshIntervalMs = 30_000;

/**
 * Track Things bridge status on an interval.
 *
 * @returns Writable store containing Things bridge status.
 */
export function useThingsBridgeStatus() {
  const state = writable<ThingsStatusState>({
    status: 'loading',
    deviceName: '',
    lastSeenAt: null
  });

  let interval: ReturnType<typeof setInterval> | null = null;

  const setState = (patch: Partial<ThingsStatusState>) => {
    state.update((current) => ({ ...current, ...patch }));
  };

  const load = async () => {
    try {
      const data = await thingsAPI.status();
      if (data.activeBridge) {
        setState({
          status: 'online',
          deviceName: data.activeBridge.deviceName,
          lastSeenAt: data.activeBridge.lastSeenAt
        });
      } else {
        setState({ status: 'offline', deviceName: '', lastSeenAt: null });
      }
    } catch (error) {
      logError('Failed to load Things bridge status', error, { scope: 'thingsBridgeStatus.load' });
      setState({ status: 'offline', deviceName: '', lastSeenAt: null });
    }
  };

  onMount(() => {
    void load();
    interval = setInterval(load, refreshIntervalMs);
  });

  onDestroy(() => {
    if (interval) clearInterval(interval);
  });

  return state;
}
