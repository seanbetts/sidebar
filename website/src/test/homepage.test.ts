import { render, screen } from '@testing-library/svelte';
import HomePage from '../routes/+page.svelte';

describe('homepage', () => {
  it('renders the product thesis and campaign close', () => {
    render(HomePage);

    expect(
      screen.getByRole('heading', { name: /your work\. your assistant\. one place\./i })
    ).toBeInTheDocument();
    expect(screen.getByText(/chat that knows your work\./i)).toBeInTheDocument();
    expect(screen.getByText(/keep sidebar open\./i)).toBeInTheDocument();
  });
});
