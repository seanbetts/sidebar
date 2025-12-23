export type ThemeMode = "light" | "dark";

export function setThemeMode(theme: ThemeMode): void {
  const root = document.documentElement;
  if (theme === "dark") {
    root.classList.add("dark");
    localStorage.setItem("theme", "dark");
  } else {
    root.classList.remove("dark");
    localStorage.setItem("theme", "light");
  }
}

export function getStoredTheme(): ThemeMode | null {
  const stored = localStorage.getItem("theme");
  if (stored === "light" || stored === "dark") {
    return stored;
  }
  return null;
}
