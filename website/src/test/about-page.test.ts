import { render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import AboutPage from '../routes/about/+page.svelte';

describe('about page', () => {
  it('uses one supporting product screenshot near the top of the founder story', () => {
    render(AboutPage);

    const images = screen.getAllByRole('img');
    expect(images).toHaveLength(1);
    expect(images[0]).toHaveAttribute('src', '/screenshots/chat-ipad.png');
    expect(images[0]).toHaveAccessibleName();
  });

  it('keeps the founder story and AI-native productivity sections intact', () => {
    render(AboutPage);

    expect(screen.getByRole('heading', { name: /about sidebar/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /why i built sidebar/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /ai-native productivity/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /get in touch/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /support@trysidebar\.ai/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /docs\.trysidebar\.ai/i })).toBeInTheDocument();
  });
});
