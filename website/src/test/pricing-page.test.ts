import { render, screen } from '@testing-library/svelte';
import { within } from '@testing-library/dom';
import { describe, expect, it } from 'vitest';
import PricingPage from '../routes/pricing/+page.svelte';

describe('pricing page', () => {
  it('renders the public pricing structure and tier cards', () => {
    render(PricingPage);

    expect(screen.getByRole('heading', { name: /pricing/i })).toBeInTheDocument();
    expect(screen.getByText(/final numbers are not/i)).toBeInTheDocument();

    const tierList = screen.getByRole('list', { name: /pricing tiers/i });

    expect(tierList.querySelectorAll(':scope > li')).toHaveLength(4);
    expect(within(tierList).getAllByRole('heading', { level: 2 })).toHaveLength(4);
    expect(screen.getByRole('heading', { name: /^free$/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /^plus$/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /^pro$/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /^byok$/i })).toBeInTheDocument();
    expect(screen.getByText(/keep subscription cost and model cost separate/i)).toBeInTheDocument();
  });
});
