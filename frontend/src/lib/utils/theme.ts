export type ThemeMode = "light" | "dark";

export function applyThemeMode(theme: ThemeMode, persist: boolean): void {
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
}

export function setThemeMode(theme: ThemeMode): void {
  applyThemeMode(theme, true);
}

export function getStoredTheme(): ThemeMode | null {
  const stored = localStorage.getItem("theme");
  if (stored === "light" || stored === "dark") {
    return stored;
  }
  return null;
}
