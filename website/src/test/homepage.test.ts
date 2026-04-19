import { render, screen } from '@testing-library/svelte';
import HomePage from '../routes/+page.svelte';

describe('homepage', () => {
  it('keeps the current hero and screenshot shell visible for the future refresh', () => {
    render(HomePage);

    expect(screen.getByRole('heading', { name: /sideBar/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /next screenshot/i })).toBeInTheDocument();
    expect(
      screen.getByRole('heading', { name: /your work\. your assistant\. one place\./i })
    ).toBeInTheDocument();
  });
});
