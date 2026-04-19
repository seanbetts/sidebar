import { render, screen, within } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import HomePage from '../routes/+page.svelte';

describe('homepage', () => {
  it('keeps the calmer canonical shared tagline', () => {
    render(HomePage);

    expect(
      screen.getByRole('heading', { level: 1, name: /your work\. your assistant\. one place\./i })
    ).toBeInTheDocument();
  });

  it('uses product screenshots and honest placeholders instead of app store assets', () => {
    render(HomePage);

    const heroImage = screen.getByRole('img', {
      name: /sideBar on iPad showing notes, chat, and saved work in one integrated workspace/i
    });
    expect(heroImage).toHaveAttribute('src', '/screenshots/overview.png');

    expect(screen.getByText(/iphone notes screenshot coming/i)).toBeInTheDocument();
    expect(screen.getByText(/iphone tasks screenshot coming/i)).toBeInTheDocument();

    const websitesImage = screen.getByRole('img', {
      name: /saved website workflow/i
    });
    expect(websitesImage).toHaveAttribute('src', '/screenshots/websites.png');

    const skillsImage = screen.getByRole('img', {
      name: /skills store/i
    });
    expect(skillsImage).toHaveAttribute('src', '/screenshots/skills-store.png');

    const closeSection = screen
      .getByRole('heading', { name: /keep sidebar open\./i })
      .closest('section');
    expect(closeSection).not.toBeNull();
    expect(within(closeSection as HTMLElement).queryByRole('img')).not.toBeInTheDocument();
  });
});
