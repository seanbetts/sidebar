import { render, screen } from '@testing-library/svelte';
import { siteCopy } from '$lib/content/siteCopy';
import HomePage from '../routes/+page.svelte';

describe('homepage', () => {
  it('anchors the planned homepage narrative while the current shell stays in place', () => {
    render(HomePage);

    expect(screen.getByRole('heading', { name: siteCopy.home.hero.headline })).toBeInTheDocument();
    expect(screen.getByText(siteCopy.home.hero.subhead)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /next screenshot/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: siteCopy.home.thesis.heading })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: siteCopy.home.close.headline })).toBeInTheDocument();
  });
});
