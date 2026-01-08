import { onDestroy, onMount } from 'svelte';
import { writable } from 'svelte/store';
import { setThemeMode } from '$lib/utils/theme';
import {
	getCachedData,
	isCacheStale,
	revalidateInBackground,
	setCachedData
} from '$lib/utils/cache';
import { logError } from '$lib/utils/errorHandling';

const locationCacheKey = 'location.live';
const locationLevelsCacheKey = 'location.levels';
const coordsCacheKey = 'location.coords';
const weatherCacheKey = 'weather.snapshot';
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
		migrateLegacyWeatherCache();
		loadLocation();
		loadWeather();
	});

	onDestroy(() => {
		if (timeInterval) clearInterval(timeInterval);
	});

	async function loadLocation() {
		const cachedLabel = getCachedData<string>(locationCacheKey, {
			ttl: locationCacheTtlMs,
			version: '1.0'
		});
		if (cachedLabel) {
			setState({ liveLocation: cachedLabel });
			return;
		}

		const coords = await getCoords();
		if (!coords) return;
		await fetchLocationLabel(coords.lat, coords.lon);
	}

	async function loadWeather() {
		const cachedWeather = getCachedData<Record<string, unknown>>(weatherCacheKey, {
			ttl: weatherCacheTtlMs,
			version: '1.0'
		});
		if (cachedWeather) {
			applyWeather(cachedWeather);
			if (isCacheStale(weatherCacheKey, weatherCacheTtlMs)) {
				const coords = await getCoords();
				if (coords) {
					revalidateInBackground(weatherCacheKey, () => fetchWeather(coords.lat, coords.lon), {
						ttl: weatherCacheTtlMs,
						version: '1.0'
					});
				}
			}
			return;
		}

		const coords = await getCoords();
		if (!coords) return;

		try {
			const data = await fetchWeather(coords.lat, coords.lon);
			applyWeather(data);
		} catch (error) {
			logError('Failed to load weather', error, { scope: 'siteHeader.loadWeather' });
		}
	}

	async function getCoords(): Promise<Coords | null> {
		const cachedCoords = getCachedData<Coords>(coordsCacheKey, {
			ttl: coordsCacheTtlMs,
			version: '1.0'
		});
		if (cachedCoords) {
			return cachedCoords;
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
						setCachedData(coordsCacheKey, coords, { ttl: coordsCacheTtlMs, version: '1.0' });
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
				`/api/v1/places/reverse?lat=${encodeURIComponent(lat)}&lng=${encodeURIComponent(lon)}`
			);
			if (!response.ok) return;
			const data = await response.json();
			const label = data?.label;
			if (label) {
				setState({ liveLocation: label });
				setCachedData(locationCacheKey, label, { ttl: locationCacheTtlMs, version: '1.0' });
			}
			if (data?.levels) {
				setCachedData(locationLevelsCacheKey, data.levels, {
					ttl: locationCacheTtlMs,
					version: '1.0'
				});
			}
		} catch (error) {
			logError('Failed to load live location', error, { scope: 'siteHeader.loadLocation' });
		}
	}

	async function fetchWeather(lat: number, lon: number): Promise<Record<string, unknown>> {
		const response = await fetch(
			`/api/v1/weather?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}`
		);
		if (!response.ok) {
			throw new Error('Weather request failed');
		}
		const data = await response.json();
		setCachedData(weatherCacheKey, data, { ttl: weatherCacheTtlMs, version: '1.0' });
		return data;
	}

	function migrateLegacyWeatherCache() {
		if (typeof window === 'undefined') return;
		try {
			const legacyWeather = localStorage.getItem('sidebar.weather');
			const legacyWeatherTs = localStorage.getItem('sidebar.weatherTs');
			if (legacyWeather && legacyWeatherTs) {
				const payload = JSON.parse(legacyWeather);
				setCachedData(weatherCacheKey, payload, { ttl: weatherCacheTtlMs, version: '1.0' });
				localStorage.removeItem('sidebar.weather');
				localStorage.removeItem('sidebar.weatherTs');
			}

			const legacyCoords = localStorage.getItem('sidebar.coords');
			const legacyCoordsTs = localStorage.getItem('sidebar.coordsTs');
			if (legacyCoords && legacyCoordsTs) {
				setCachedData(coordsCacheKey, JSON.parse(legacyCoords), {
					ttl: coordsCacheTtlMs,
					version: '1.0'
				});
				localStorage.removeItem('sidebar.coords');
				localStorage.removeItem('sidebar.coordsTs');
			}

			const legacyLocation = localStorage.getItem('sidebar.liveLocation');
			const legacyLocationTs = localStorage.getItem('sidebar.liveLocationTs');
			if (legacyLocation && legacyLocationTs) {
				setCachedData(locationCacheKey, legacyLocation, {
					ttl: locationCacheTtlMs,
					version: '1.0'
				});
				localStorage.removeItem('sidebar.liveLocation');
				localStorage.removeItem('sidebar.liveLocationTs');
			}

			const legacyLevels = localStorage.getItem('sidebar.liveLocationLevels');
			if (legacyLevels) {
				setCachedData(locationLevelsCacheKey, JSON.parse(legacyLevels), {
					ttl: locationCacheTtlMs,
					version: '1.0'
				});
				localStorage.removeItem('sidebar.liveLocationLevels');
			}
		} catch (error) {
			console.warn('Legacy location/weather cache migration failed:', error);
		}
	}

	function applyWeather(data: { temperature_c?: number; weather_code?: number; is_day?: number }) {
		if (typeof data.temperature_c === 'number') {
			setState({ weatherTemp: `${Math.round(data.temperature_c)}°C` });
		}

		const weatherCode = typeof data.weather_code === 'number' ? data.weather_code : null;
		const weatherIsDay = typeof data.is_day === 'number' ? data.is_day : null;
		setState({ weatherCode, weatherIsDay });

		if (weatherIsDay !== null) {
			setThemeMode(weatherIsDay === 1 ? 'light' : 'dark', 'weather');
		}
	}

	return state;
}
