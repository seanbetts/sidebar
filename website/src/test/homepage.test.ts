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

    expect(
      screen.queryByRole('heading', { name: /work and assistant, together\./i })
    ).not.toBeInTheDocument();

    const heroImage = screen.getByRole('img', {
      name: /sideBar on iPad showing notes, chat, and saved work in one integrated workspace/i
    });
    expect(heroImage).toHaveAttribute('src', '/screenshots/welcome-ipad.png');

    const chatImage = screen.getByRole('img', {
      name: /chat on iPhone/i
    });
    expect(chatImage).toHaveAttribute('src', '/screenshots/chat-iphone.png');

    const notesImage = screen.getByRole('img', {
      name: /notes on iPad/i
    });
    expect(notesImage).toHaveAttribute('src', '/screenshots/notes-ipad.png');

    const tasksImage = screen.getByRole('img', {
      name: /tasks on iPhone/i
    });
    expect(tasksImage).toHaveAttribute('src', '/screenshots/tasks-iphone.png');

    const websitesImage = screen.getByRole('img', {
      name: /websites on iPad/i
    });
    expect(websitesImage).toHaveAttribute('src', '/screenshots/websites-ipad.png');

    const skillsImage = screen.getByRole('img', {
      name: /skills store on iPhone/i
    });
    expect(skillsImage).toHaveAttribute('src', '/screenshots/skills-store-iphone.png');

    const closeSection = screen
      .getByRole('heading', { name: /keep sidebar open\./i })
      .closest('section');
    expect(closeSection).not.toBeNull();
    expect(within(closeSection as HTMLElement).queryByRole('img')).not.toBeInTheDocument();
  });
});
