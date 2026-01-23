import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import {
	normalizeDateKey,
	todayKey,
	offsetDateKey,
	classifyDueBucket
} from '$lib/stores/tasks-utils';

describe('tasks-utils', () => {
	describe('normalizeDateKey', () => {
		it('extracts date portion from ISO string', () => {
			expect(normalizeDateKey('2026-01-23T12:34:56.789Z')).toBe('2026-01-23');
		});

		it('handles already normalized date', () => {
			expect(normalizeDateKey('2026-01-23')).toBe('2026-01-23');
		});

		it('extracts first 10 characters', () => {
			expect(normalizeDateKey('2026-12-31T00:00:00')).toBe('2026-12-31');
		});
	});

	describe('todayKey', () => {
		beforeEach(() => {
			vi.useFakeTimers();
		});

		afterEach(() => {
			vi.useRealTimers();
		});

		it('returns today date in YYYY-MM-DD format', () => {
			vi.setSystemTime(new Date('2026-01-23T15:30:00Z'));
			expect(todayKey()).toBe('2026-01-23');
		});

		it('handles different timezones correctly', () => {
			vi.setSystemTime(new Date('2026-06-15T08:00:00Z'));
			expect(todayKey()).toBe('2026-06-15');
		});
	});

	describe('offsetDateKey', () => {
		beforeEach(() => {
			vi.useFakeTimers();
			vi.setSystemTime(new Date('2026-01-23T12:00:00'));
		});

		afterEach(() => {
			vi.useRealTimers();
		});

		it('returns tomorrow for offset 1', () => {
			expect(offsetDateKey(1)).toBe('2026-01-24');
		});

		it('returns yesterday for offset -1', () => {
			expect(offsetDateKey(-1)).toBe('2026-01-22');
		});

		it('returns same day for offset 0', () => {
			expect(offsetDateKey(0)).toBe('2026-01-23');
		});

		it('handles week offset', () => {
			expect(offsetDateKey(7)).toBe('2026-01-30');
		});

		it('handles month boundary', () => {
			vi.setSystemTime(new Date('2026-01-30T12:00:00'));
			expect(offsetDateKey(5)).toBe('2026-02-04');
		});
	});

	describe('classifyDueBucket', () => {
		beforeEach(() => {
			vi.useFakeTimers();
			vi.setSystemTime(new Date('2026-01-23T12:00:00'));
		});

		afterEach(() => {
			vi.useRealTimers();
		});

		it('returns today for current date', () => {
			expect(classifyDueBucket('2026-01-23')).toBe('today');
		});

		it('returns upcoming for future date', () => {
			expect(classifyDueBucket('2026-01-24')).toBe('upcoming');
		});

		it('returns upcoming for past date', () => {
			expect(classifyDueBucket('2026-01-22')).toBe('upcoming');
		});

		it('handles full ISO string', () => {
			expect(classifyDueBucket('2026-01-23T15:30:00Z')).toBe('today');
		});
	});
});
