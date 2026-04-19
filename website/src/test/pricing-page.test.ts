import { render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import PricingPage from '../routes/pricing/+page.svelte';

describe('pricing page', () => {
  it('renders the public pricing structure and keeps screenshots off pricing', () => {
    render(PricingPage);

    expect(screen.getByRole('heading', { name: /pricing/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /^free$/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /^plus$/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /^pro$/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /^byok$/i })).toBeInTheDocument();
    expect(document.querySelector('img[src^="/screenshots/"]')).toBeNull();
  });
});
