import { fireEvent, render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import EarlyAccessPage from '../routes/early-access/+page.svelte';

describe('early access page', () => {
  it('frames early access as list capture, not immediate product access', () => {
    render(EarlyAccessPage);

    expect(screen.getByRole('heading', { name: /join the early access list/i })).toBeInTheDocument();
    expect(
      screen.getByText(/joining the list does not mean immediate access/i)
    ).toBeInTheDocument();
    expect(
      screen.getByText(/priority is people who can try sidebar on iphone, ipad, and mac/i)
    ).toBeInTheDocument();
    expect(screen.getByText(/selected people receive beta invites/i)).toBeInTheDocument();
  });

  it('lets people complete a form before sending the request', async () => {
    render(EarlyAccessPage);

    await fireEvent.input(screen.getByLabelText(/^name$/i), {
      target: { value: 'Sean Betts' }
    });
    await fireEvent.input(screen.getByLabelText(/^email$/i), {
      target: { value: 'sean@example.com' }
    });
    await fireEvent.click(screen.getByLabelText(/^iphone$/i));
    await fireEvent.input(screen.getByLabelText(/how did you hear about sidebar/i), {
      target: { value: 'Substack' }
    });
    await fireEvent.input(screen.getByLabelText(/how do you hope to use it/i), {
      target: { value: 'For notes and planning.' }
    });

    expect(screen.getByRole('form', { name: /early access form/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /send request/i })).toHaveAttribute(
      'href',
      expect.stringContaining('mailto:support@trysidebar.ai?subject=')
    );
    expect(screen.getByRole('link', { name: /send request/i })).toHaveAttribute(
      'href',
      expect.stringContaining(encodeURIComponent('Name: Sean Betts'))
    );
    expect(screen.getByRole('link', { name: /send request/i })).toHaveAttribute(
      'href',
      expect.stringContaining(encodeURIComponent('Email: sean@example.com'))
    );
    expect(screen.getByRole('link', { name: /send request/i })).toHaveAttribute(
      'href',
      expect.stringContaining(encodeURIComponent('Devices (iPhone, iPad, Mac): iPhone'))
    );
    expect(screen.getByRole('link', { name: /see planned pricing/i })).toHaveAttribute(
      'href',
      '/pricing'
    );
  });
});
