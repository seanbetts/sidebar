import { render, screen } from '@testing-library/svelte';
import Nav from '../lib/components/Nav.svelte';
import Footer from '../lib/components/Footer.svelte';

describe('marketing shell', () => {
  it('shows about, pricing, docs, and the primary CTA in nav', () => {
    render(Nav);

    expect(screen.getByRole('link', { name: /about/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /pricing/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /docs/i })).toBeInTheDocument();
  });

  it('shows docs and support links in the footer', () => {
    render(Footer);

    expect(screen.getByRole('link', { name: /privacy policy/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /terms of service/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /contact/i })).toBeInTheDocument();
  });
});
