import { render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import AboutPage from '../routes/about/+page.svelte';

describe('about page', () => {
  it('keeps screenshots off the about page', () => {
    render(AboutPage);

    expect(screen.queryByRole('img')).not.toBeInTheDocument();
  });

  it('keeps the founder story intact', () => {
    render(AboutPage);

    expect(screen.getByText(/founder note/i)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /why i built sidebar/i })).toBeInTheDocument();
    expect(screen.getByText(/personality, a point of view/i)).toBeInTheDocument();
    expect(screen.getByText(/skills are a big part of that/i)).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: /get in touch/i })).not.toBeInTheDocument();
  });
});
