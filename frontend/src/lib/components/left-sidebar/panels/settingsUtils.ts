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

export function normalizeSkillList(list: string[]) {
  return [...new Set(list)].sort().join('|');
}
