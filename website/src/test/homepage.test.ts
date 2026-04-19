import { render, screen } from '@testing-library/svelte';
import HomePage from '../routes/+page.svelte';

describe('homepage', () => {
  it('anchors the planned homepage narrative while the current shell stays in place', () => {
    render(HomePage);

    expect(
      screen.getByRole('heading', { name: /your work\. your assistant\. one place\./i })
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /next screenshot/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /work and assistant, together\./i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /keep sidebar open\./i })).toBeInTheDocument();
  });
});
