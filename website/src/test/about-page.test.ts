import { render, screen } from '@testing-library/svelte';
import AboutPage from '../routes/about/+page.svelte';

describe('about page', () => {
  it('explains the copy-paste loop and AI-native productivity framing', () => {
    render(AboutPage);

    expect(screen.getByText(/copy-paste loop/i)).toBeInTheDocument();
    expect(screen.getByText(/ai-native productivity/i)).toBeInTheDocument();
  });
});
