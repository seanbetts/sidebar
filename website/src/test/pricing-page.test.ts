import { render, screen } from '@testing-library/svelte';
import Nav from '../lib/components/Nav.svelte';

describe('pricing surface', () => {
  it('keeps the navigation ready for the planned pricing route', () => {
    render(Nav);

    expect(screen.getByRole('link', { name: /about/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /docs/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /pricing/i })).toBeInTheDocument();
  });
});
