<script lang="ts">
	import { onDestroy, onMount } from "svelte";
	import ModeToggle from "$lib/components/mode-toggle.svelte";
	import ScratchpadPopover from "$lib/components/scratchpad-popover.svelte";
	import { Cloud, CloudDrizzle, CloudFog, CloudHail, CloudLightning, CloudMoon, CloudMoonRain, CloudRain, CloudSnow, CloudSun, CloudSunRain, Moon, Sun } from "lucide-svelte";
	import { applyThemeMode, getStoredTheme } from "$lib/utils/theme";

	let currentDate = "";
	let currentTime = "";
	let liveLocation = "";
	let weatherTemp = "";
	let weatherCode: number | null = null;
	let weatherIsDay: number | null = null;
	let timeInterval: ReturnType<typeof setInterval> | undefined;
	const locationCacheKey = "sidebar.liveLocation";
	const locationCacheTimeKey = "sidebar.liveLocationTs";
	const locationCacheLevelsKey = "sidebar.liveLocationLevels";
	const coordsCacheKey = "sidebar.coords";
	const coordsCacheTimeKey = "sidebar.coordsTs";
	const weatherCacheKey = "sidebar.weather";
	const weatherCacheTimeKey = "sidebar.weatherTs";
	const locationCacheTtlMs = 30 * 60 * 1000;
	const coordsCacheTtlMs = 24 * 60 * 60 * 1000;
	const weatherCacheTtlMs = 30 * 60 * 1000;
	let coordsPromise: Promise<{ lat: number; lon: number } | null> | null = null;

	function updateDateTime() {
		const now = new Date();
		currentDate = new Intl.DateTimeFormat(undefined, {
			weekday: "short",
			month: "short",
			day: "2-digit"
		}).format(now);
		currentTime = new Intl.DateTimeFormat(undefined, {
			hour: "2-digit",
			minute: "2-digit"
		}).format(now);
	}

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
		if (typeof window === "undefined") {
			return;
		}

		const cachedLabel = localStorage.getItem(locationCacheKey);
		const cachedTime = localStorage.getItem(locationCacheTimeKey);
		if (cachedLabel && cachedTime) {
			const age = Date.now() - Number(cachedTime);
			if (!Number.isNaN(age) && age < locationCacheTtlMs) {
				liveLocation = cachedLabel;
				return;
			}
		}

		const coords = await getCoords();
		if (!coords) {
			return;
		}
		await fetchLocationLabel(coords.lat, coords.lon);
	}

	async function loadWeather() {
		if (typeof window === "undefined") {
			return;
		}
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
					console.error("Failed to parse weather cache:", error);
				}
			}
		}

		const coords = await getCoords();
		if (!coords) {
			return;
		}

		try {
			const response = await fetch(
				`/api/weather?lat=${encodeURIComponent(coords.lat)}&lon=${encodeURIComponent(coords.lon)}`
			);
			if (!response.ok) {
				return;
			}
			const data = await response.json();
			applyWeather(data);
			localStorage.setItem(weatherCacheKey, JSON.stringify(data));
			localStorage.setItem(weatherCacheTimeKey, Date.now().toString());
		} catch (error) {
			console.error("Failed to load weather:", error);
		}
	}

	async function getCoords(): Promise<{ lat: number; lon: number } | null> {
		const cachedCoords = localStorage.getItem(coordsCacheKey);
		const cachedTime = localStorage.getItem(coordsCacheTimeKey);
		if (cachedCoords && cachedTime) {
			const age = Date.now() - Number(cachedTime);
			if (!Number.isNaN(age) && age < coordsCacheTtlMs) {
				try {
					return JSON.parse(cachedCoords);
				} catch (error) {
					console.error("Failed to parse coords cache:", error);
				}
			}
		}

		if (!navigator.geolocation) {
			return null;
		}

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
			if (!response.ok) {
				return;
			}
			const data = await response.json();
			const label = data?.label;
			if (label) {
				liveLocation = label;
				localStorage.setItem(locationCacheKey, label);
				localStorage.setItem(locationCacheTimeKey, Date.now().toString());
			}
			if (data?.levels) {
				localStorage.setItem(locationCacheLevelsKey, JSON.stringify(data.levels));
			}
		} catch (error) {
			console.error("Failed to load live location:", error);
		}
	}

	function applyWeather(data: {
		temperature_c?: number;
		weather_code?: number;
		is_day?: number;
	}) {
		if (typeof data.temperature_c === "number") {
			weatherTemp = `${Math.round(data.temperature_c)}°C`;
		}
		weatherCode = typeof data.weather_code === "number" ? data.weather_code : null;
		weatherIsDay = typeof data.is_day === "number" ? data.is_day : null;

		if (weatherIsDay !== null) {
			applyThemeMode(weatherIsDay === 1 ? "light" : "dark", false);
		}
	}

	function resolveWeatherIcon(code: number | null, isDay: number | null) {
		if (code === null) return Cloud;
		const isDaytime = isDay === 1;
		if (code === 0) return isDaytime ? Sun : Moon;
		if (code <= 2) return isDaytime ? CloudSun : CloudMoon;
		if (code === 3) return Cloud;
		if (code >= 45 && code <= 48) return CloudFog;
		if (code >= 51 && code <= 57) return CloudDrizzle;
		if (code >= 61 && code <= 65) return CloudRain;
		if (code >= 66 && code <= 67) return CloudHail;
		if (code >= 80 && code <= 82) return isDaytime ? CloudSunRain : CloudMoonRain;
		if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return CloudSnow;
		if (code >= 95) return CloudLightning;
		return Cloud;
	}
</script>

<header class="site-header">
	<div class="brand">
		<img src="/images/logo.svg" alt="sideBar" class="brand-logo" />
		<span class="brand-mark" aria-hidden="true"></span>
		<div class="brand-text">
			<div class="title">sideBar</div>
			<div class="subtitle">Workspace</div>
		</div>
	</div>
	<div class="actions">
		<div class="datetime-group">
			{#if weatherTemp || liveLocation}
				<div class="weather-location">
					{#if weatherTemp}
						<span class="weather">
							<svelte:component this={resolveWeatherIcon(weatherCode, weatherIsDay)} size={16} />
							<span class="weather-temp">{weatherTemp}</span>
						</span>
					{/if}
					{#if liveLocation}
						<span class="location">{liveLocation}</span>
					{/if}
				</div>
			{/if}
			<div class="datetime">
				<span class="date">{currentDate}</span>
				<span class="time">{currentTime}</span>
			</div>
		</div>
		<ScratchpadPopover />
		<ModeToggle />
	</div>
</header>

<style>
	:global(:root) {
		--site-header-height: 64px;
	}

	.site-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		height: var(--site-header-height);
		padding: 0.75rem 1.5rem;
		border-bottom: 1px solid var(--color-border);
		background: linear-gradient(90deg, rgba(0, 0, 0, 0.04), rgba(0, 0, 0, 0));
	}

	.brand {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

	.brand-logo {
		height: 2rem;
		width: auto;
	}

	:global(.dark) .brand-logo {
		filter: invert(1);
	}

	.brand-mark {
		height: 2.25rem;
		width: 0.25rem;
		border-radius: 999px;
		background-color: var(--color-primary);
	}

	.brand-text {
		display: flex;
		flex-direction: column;
	}

	.title {
		font-size: 1.125rem;
		font-weight: 700;
		letter-spacing: 0.01em;
		color: var(--color-foreground);
	}

	.subtitle {
		font-size: 0.75rem;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-muted-foreground);
	}

	.actions {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.datetime-group {
		display: flex;
		align-items: center;
		gap: 1.25rem;
		margin-right: 1.25rem;
	}

	.weather-location {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 0.15rem;
	}

	.datetime {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 0.1rem;
	}

	.location {
		font-size: 0.75rem;
		letter-spacing: 0.02em;
		text-transform: uppercase;
		color: var(--color-muted-foreground);
		white-space: nowrap;
	}

	.weather {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		color: var(--color-foreground);
		font-size: 0.95rem;
		font-weight: 600;
	}

	.weather :global(svg) {
		width: 16px;
		height: 16px;
	}



	.date {
		font-size: 0.75rem;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--color-muted-foreground);
	}

	.time {
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-foreground);
	}
</style>
