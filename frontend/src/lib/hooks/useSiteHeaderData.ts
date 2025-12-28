import { onDestroy, onMount } from 'svelte';
import { writable } from 'svelte/store';
import { applyThemeMode } from '$lib/utils/theme';

const locationCacheKey = 'sidebar.liveLocation';
const locationCacheTimeKey = 'sidebar.liveLocationTs';
const locationCacheLevelsKey = 'sidebar.liveLocationLevels';
const coordsCacheKey = 'sidebar.coords';
const coordsCacheTimeKey = 'sidebar.coordsTs';
const weatherCacheKey = 'sidebar.weather';
const weatherCacheTimeKey = 'sidebar.weatherTs';
const locationCacheTtlMs = 30 * 60 * 1000;
const coordsCacheTtlMs = 24 * 60 * 60 * 1000;
const weatherCacheTtlMs = 30 * 60 * 1000;

type Coords = { lat: number; lon: number };

type SiteHeaderState = {
  currentDate: string;
  currentTime: string;
  liveLocation: string;
  weatherTemp: string;
  weatherCode: number | null;
  weatherIsDay: number | null;
};

/**
 * Manage live date/time, location, and weather state for the header.
 *
 * @returns Writable store with live header data.
 */
export function useSiteHeaderData() {
  const state = writable<SiteHeaderState>({
    currentDate: '',
    currentTime: '',
    liveLocation: '',
    weatherTemp: '',
    weatherCode: null,
    weatherIsDay: null
  });

  let timeInterval: ReturnType<typeof setInterval> | null = null;
  let coordsPromise: Promise<Coords | null> | null = null;

  const setState = (patch: Partial<SiteHeaderState>) => {
    state.update((current) => ({ ...current, ...patch }));
  };

  const updateDateTime = () => {
    const now = new Date();
    setState({
      currentDate: new Intl.DateTimeFormat(undefined, {
        weekday: 'short',
        month: 'short',
        day: '2-digit'
      }).format(now),
      currentTime: new Intl.DateTimeFormat(undefined, {
        hour: '2-digit',
        minute: '2-digit'
      }).format(now)
    });
  };

  onMount(() => {
    updateDateTime();
    timeInterval = setInterval(updateDateTime, 60_000);
    loadLocation();
    loadWeather();
  });

  onDestroy(() => {
    if (timeInterval) clearInterval(timeInterval);
  });

  async function loadLocation() {
    if (typeof window === 'undefined') return;

    const cachedLabel = localStorage.getItem(locationCacheKey);
    const cachedTime = localStorage.getItem(locationCacheTimeKey);
    if (cachedLabel && cachedTime) {
      const age = Date.now() - Number(cachedTime);
      if (!Number.isNaN(age) && age < locationCacheTtlMs) {
        setState({ liveLocation: cachedLabel });
        return;
      }
    }

    const coords = await getCoords();
    if (!coords) return;
    await fetchLocationLabel(coords.lat, coords.lon);
  }

  async function loadWeather() {
    if (typeof window === 'undefined') return;

    const cachedWeather = localStorage.getItem(weatherCacheKey);
    const cachedTime = localStorage.getItem(weatherCacheTimeKey);
    if (cachedWeather && cachedTime) {
      const age = Date.now() - Number(cachedTime);
      if (!Number.isNaN(age) && age < weatherCacheTtlMs) {
        try {
          const data = JSON.parse(cachedWeather);
          applyWeather(data);
          return;
        } catch (error) {
          console.error('Failed to parse weather cache:', error);
        }
      }
    }

    const coords = await getCoords();
    if (!coords) return;

    try {
      const response = await fetch(
        `/api/weather?lat=${encodeURIComponent(coords.lat)}&lon=${encodeURIComponent(coords.lon)}`
      );
      if (!response.ok) return;
      const data = await response.json();
      applyWeather(data);
      localStorage.setItem(weatherCacheKey, JSON.stringify(data));
      localStorage.setItem(weatherCacheTimeKey, Date.now().toString());
    } catch (error) {
      console.error('Failed to load weather:', error);
    }
  }

  async function getCoords(): Promise<Coords | null> {
    const cachedCoords = localStorage.getItem(coordsCacheKey);
    const cachedTime = localStorage.getItem(coordsCacheTimeKey);
    if (cachedCoords && cachedTime) {
      const age = Date.now() - Number(cachedTime);
      if (!Number.isNaN(age) && age < coordsCacheTtlMs) {
        try {
          return JSON.parse(cachedCoords);
        } catch (error) {
          console.error('Failed to parse coords cache:', error);
        }
      }
    }

    if (!navigator.geolocation) return null;

    if (!coordsPromise) {
      coordsPromise = new Promise((resolve) => {
        navigator.geolocation.getCurrentPosition(
          (position) => {
            const coords = {
              lat: position.coords.latitude,
              lon: position.coords.longitude
            };
            localStorage.setItem(coordsCacheKey, JSON.stringify(coords));
            localStorage.setItem(coordsCacheTimeKey, Date.now().toString());
            resolve(coords);
          },
          () => {
            resolve(null);
          },
          { enableHighAccuracy: false, maximumAge: coordsCacheTtlMs, timeout: 8000 }
        );
      });
    }

    const result = await coordsPromise;
    coordsPromise = null;
    return result;
  }

  async function fetchLocationLabel(lat: number, lon: number) {
    try {
      const response = await fetch(
        `/api/places/reverse?lat=${encodeURIComponent(lat)}&lng=${encodeURIComponent(lon)}`
      );
      if (!response.ok) return;
      const data = await response.json();
      const label = data?.label;
      if (label) {
        setState({ liveLocation: label });
        localStorage.setItem(locationCacheKey, label);
        localStorage.setItem(locationCacheTimeKey, Date.now().toString());
      }
      if (data?.levels) {
        localStorage.setItem(locationCacheLevelsKey, JSON.stringify(data.levels));
      }
    } catch (error) {
      console.error('Failed to load live location:', error);
    }
  }

  function applyWeather(data: {
    temperature_c?: number;
    weather_code?: number;
    is_day?: number;
  }) {
    if (typeof data.temperature_c === 'number') {
      setState({ weatherTemp: `${Math.round(data.temperature_c)}°C` });
    }

    const weatherCode = typeof data.weather_code === 'number' ? data.weather_code : null;
    const weatherIsDay = typeof data.is_day === 'number' ? data.is_day : null;
    setState({ weatherCode, weatherIsDay });

    if (weatherIsDay !== null) {
      applyThemeMode(weatherIsDay === 1 ? 'light' : 'dark', false);
    }
  }

  return state;
}
