import { MARKETING_COPY } from '../../../../shared/marketingCopy';

export const siteCopy = {
  home: {
    hero: {
      eyebrow: 'AI-native productivity',
      headline: MARKETING_COPY.tagline,
      subhead:
        'sideBar puts your notes, tasks, saved websites, and files alongside an assistant that can work with all of them, so help starts with context instead of a blank chat.',
      primaryCta: 'Request Early Access',
      secondaryCta: 'Read the Docs'
    },
    thesis: {
      heading: 'Work and assistant, together.',
      body:
        'Most AI products still make you ferry context between a chat box and the rest of your tools. sideBar is built so your work and your assistant share the same place.'
    },
    proofs: [
      {
        heading: 'Chat that knows your work.',
        body: 'Ask for help from inside the same environment where your notes, tasks, files, and saved pages already live.',
        image: '/screenshots/story/iphone-screen-2.png',
        alt: 'sideBar chat screen showing an onboarding conversation with contextual help'
      }
    ],
    close: {
      headline: 'Keep sideBar open.',
      body: 'Chat. Notes. Tasks. Sites. Skills.'
    }
  }
} as const;
