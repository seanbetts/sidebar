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

    const notesSection = screen
      .getByRole('heading', { name: /notes with a helping hand\./i })
      .closest('section');
    expect(notesSection).not.toBeNull();
    expect(within(notesSection as HTMLElement).getByRole('img')).toHaveAttribute(
      'aria-label'
    );
    expect(notesSection?.querySelector('img')).toBeNull();

    const tasksSection = screen
      .getByRole('heading', { name: /tasks, planned together\./i })
      .closest('section');
    expect(tasksSection).not.toBeNull();
    expect(within(tasksSection as HTMLElement).getByRole('img')).toHaveAttribute(
      'aria-label'
    );
    expect(tasksSection?.querySelector('img')).toBeNull();

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
