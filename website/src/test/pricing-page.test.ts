import { fireEvent, render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import PricingPage from '../routes/pricing/+page.svelte';

describe('pricing page', () => {
  it('renders the public pricing structure and keeps screenshots off pricing', async () => {
    render(PricingPage);

    expect(screen.getByRole('heading', { name: /pricing/i })).toBeInTheDocument();
    const tierHeadings = screen
      .getAllByRole('heading', { level: 2 })
      .map((heading) => heading.textContent?.trim()?.replace(/\s+/g, ' '));
    expect(tierHeadings).toEqual(['Free', 'BYOK', 'Plus', 'Pro']);
    expect(screen.getByText('£0')).toBeInTheDocument();
    expect(screen.getByText('£5/mo')).toBeInTheDocument();
    expect(screen.getByText('£15/mo')).toBeInTheDocument();
    expect(screen.getByText(/^Try it free$/i)).toBeInTheDocument();
    expect(screen.getByText(/^Bring your own key$/i)).toBeInTheDocument();
    expect(screen.getByText(/^Everyday use$/i)).toBeInTheDocument();
    expect(screen.getByText(/^Pro use$/i)).toBeInTheDocument();
    expect(screen.getAllByText(/coming soon/i)).toHaveLength(2);
    expect(screen.getByText(/^Use the core app features without the assistant\.$/i)).toBeInTheDocument();
    expect(screen.queryByText(/the plan is public now/i)).not.toBeInTheDocument();
    expect(document.querySelector('.tiers-section .pixel-divider')).toBeNull();
    expect(screen.getByRole('button', { name: /monthly/i })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('button', { name: /annual/i })).toHaveAttribute('aria-pressed', 'false');

    await fireEvent.click(screen.getByRole('button', { name: /annual/i }));

    expect(screen.getByRole('button', { name: /monthly/i })).toHaveAttribute('aria-pressed', 'false');
    expect(screen.getByRole('button', { name: /annual/i })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByText('£50/yr')).toBeInTheDocument();
    expect(screen.getByText('£80/yr')).toBeInTheDocument();
    expect(screen.getByText('£150/yr')).toBeInTheDocument();
    expect(document.querySelector('img[src^="/screenshots/"]')).toBeNull();
  });
});
