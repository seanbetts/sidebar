import { render, screen } from '@testing-library/svelte';
import PricingPage from '../routes/pricing/+page.svelte';

describe('pricing page', () => {
  it('keeps the planned pricing tiers contract visible for later implementation', () => {
    render(PricingPage);

    expect(screen.getByRole('heading', { name: /pricing/i })).toBeInTheDocument();
    expect(screen.getByText(/^free$/i)).toBeInTheDocument();
    expect(screen.getByText(/^plus$/i)).toBeInTheDocument();
    expect(screen.getByText(/^pro$/i)).toBeInTheDocument();
    expect(screen.getByText(/^byok$/i)).toBeInTheDocument();
  });
});
