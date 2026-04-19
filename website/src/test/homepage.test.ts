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

    const expectPlaceholderSlot = (headingName: RegExp, keyword: RegExp) => {
      const section = screen.getByRole('heading', { name: headingName }).closest('section');
      expect(section).not.toBeNull();

      const placeholder = within(section as HTMLElement).getByRole('img');
      expect(placeholder.tagName).toBe('DIV');

      const label = placeholder.getAttribute('aria-label') ?? '';
      expect(label).toMatch(keyword);
      expect(label).toMatch(/iphone/i);
      expect(label).toMatch(/screenshot|placeholder/i);

      expect(section?.querySelector('img')).toBeNull();
    };

    expectPlaceholderSlot(/notes with a helping hand\./i, /notes/i);

    expectPlaceholderSlot(/tasks, planned together\./i, /tasks/i);

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
