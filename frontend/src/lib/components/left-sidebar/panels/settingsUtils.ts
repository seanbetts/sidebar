/**
 * Group skills by category and sort categories alphabetically.
 *
 * @param list - Array of skills to group.
 * @returns Sorted array of category entries with grouped skills.
 */
export function groupSkills(
  list: Array<{ id: string; name: string; description: string; category?: string }>
) {
  const groups = new Map<string, typeof list>();
  list.forEach((skill) => {
    const category = skill.category || 'Other';
    if (!groups.has(category)) {
      groups.set(category, []);
    }
    groups.get(category)?.push(skill);
  });
  return Array.from(groups.entries()).sort((a, b) => a[0].localeCompare(b[0]));
}

/**
 * Normalize a list of skill IDs into a stable string.
 *
 * @param list - Skill IDs to normalize.
 * @returns Sorted, deduplicated string joined by "|".
 */
export function normalizeSkillList(list: string[]) {
  return [...new Set(list)].sort().join('|');
}
