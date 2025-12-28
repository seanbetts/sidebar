export type ThemeMode = "light" | "dark";

/**
 * Apply a theme mode and optionally persist to localStorage.
 *
 * @param theme - Theme mode to apply.
 * @param persist - Whether to store the choice in localStorage.
 */
export function applyThemeMode(theme: ThemeMode, persist: boolean): void {
  if (typeof document === "undefined") {
    return;
  }
  const root = document.documentElement;
  if (theme === "dark") {
    root.classList.add("dark");
    if (persist) {
      localStorage.setItem("theme", "dark");
    }
  } else {
    root.classList.remove("dark");
    if (persist) {
      localStorage.setItem("theme", "light");
    }
  }
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent("themechange", { detail: { theme } }));
  }
}

/**
 * Set and persist a theme mode.
 *
 * @param theme - Theme mode to apply.
 */
export function setThemeMode(theme: ThemeMode): void {
  applyThemeMode(theme, true);
}

/**
 * Read the stored theme preference from localStorage.
 *
 * @returns Stored theme mode or null when unset.
 */
export function getStoredTheme(): ThemeMode | null {
  const stored = localStorage.getItem("theme");
  if (stored === "light" || stored === "dark") {
    return stored;
  }
  return null;
}
