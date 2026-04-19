import { render, screen } from '@testing-library/svelte';
import AboutPage from '../routes/about/+page.svelte';

describe('about page', () => {
  it('keeps the current about-page structure while the new story is staged', () => {
    render(AboutPage);

    expect(screen.getByRole('heading', { name: /about sidebar/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /why i built sidebar/i })).toBeInTheDocument();
    expect(screen.getByText(/copy-paste loop/i)).toBeInTheDocument();
  });
});
