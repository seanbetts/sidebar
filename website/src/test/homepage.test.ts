import { render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import HomePage from '../routes/+page.svelte';
import { MARKETING_COPY } from '../../../shared/marketingCopy';

describe('homepage', () => {
  it('uses the calmer canonical shared tagline', () => {
    expect(MARKETING_COPY.tagline).toBe('Your work. Your assistant. One place.');
  });

  it('renders the approved homepage proof sequence', () => {
    render(HomePage);

    const narrativeSequence = screen
      .getAllByRole('heading')
      .map((heading) => heading.textContent?.trim())
      .filter((heading): heading is string =>
        [
          'Work and assistant, together.',
          'Notes with a helping hand.',
          'Tasks, planned together.',
          'Save a page, ask about it later.',
          'An assistant that grows with you.',
          'Keep sideBar open.'
        ].includes(heading)
      );

    expect(narrativeSequence).toEqual([
      'Work and assistant, together.',
      'Notes with a helping hand.',
      'Tasks, planned together.',
      'Save a page, ask about it later.',
      'An assistant that grows with you.',
      'Keep sideBar open.'
    ]);

    expect(
      screen.queryByRole('heading', { name: 'Chat that knows your work.' })
    ).not.toBeInTheDocument();
  });
});
