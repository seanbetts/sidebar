import { render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import AboutPage from '../routes/about/+page.svelte';

describe('about page', () => {
  it('renders the positioning story and AI-native productivity direction', () => {
    render(AboutPage);

    expect(screen.getByRole('heading', { name: /about sidebar/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /why i built sidebar/i })).toBeInTheDocument();
    expect(screen.getByText(/copy-paste.*loop/i)).toBeInTheDocument();
    expect(screen.getByText(/right environment/i)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /ai-native productivity/i })).toBeInTheDocument();
    expect(screen.getByText(/category.*emerging/i)).toBeInTheDocument();
    expect(screen.getByText(/heading in that direction/i)).toBeInTheDocument();
  });
});
