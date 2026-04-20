import { render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import Nav from '../lib/components/Nav.svelte';
import Footer from '../lib/components/Footer.svelte';

describe('marketing shell', () => {
  it('shows home, about, pricing, docs, and the primary CTA in nav', () => {
    render(Nav);

    expect(screen.getByRole('link', { name: /^home$/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /about/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /pricing/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /docs/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /request early access/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /switch to (light|dark) mode/i })).toBeInTheDocument();
  });

  it('shows the final footer information architecture', () => {
    render(Footer);

    expect(screen.getByRole('link', { name: /privacy policy/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /terms of service/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^eula$/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /contact/i })).toBeInTheDocument();
    expect(screen.getByText(/Registered in England and Wales, company number 17137829\./i)).toBeInTheDocument();
    expect(screen.getByText(/Registered office: 66 Paul Street, London, EC2A 4NA\./i)).toBeInTheDocument();
  });
});
