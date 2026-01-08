export const normalizeDateKey = (value: string) => value.slice(0, 10);

export const todayKey = () => normalizeDateKey(new Date().toISOString());

export const offsetDateKey = (days: number) => {
	const date = new Date();
	date.setDate(date.getDate() + days);
	return normalizeDateKey(date.toISOString());
};

export const classifyDueBucket = (value: string): 'today' | 'upcoming' => {
	const date = new Date(`${normalizeDateKey(value)}T00:00:00`);
	const today = new Date();
	today.setHours(0, 0, 0, 0);
	return date.getTime() === today.getTime() ? 'today' : 'upcoming';
};
