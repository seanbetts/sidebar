import {
	Cloud,
	CloudDrizzle,
	CloudFog,
	CloudHail,
	CloudLightning,
	CloudMoon,
	CloudMoonRain,
	CloudRain,
	CloudSnow,
	CloudSun,
	CloudSunRain,
	Moon,
	Sun
} from 'lucide-svelte';

/**
 * Resolve a weather code into the corresponding icon component.
 *
 * @param code - Weather code or null.
 * @param isDay - Daytime flag from the API.
 * @returns Icon component for the weather conditions.
 */
export function resolveWeatherIcon(code: number | null, isDay: number | null) {
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
