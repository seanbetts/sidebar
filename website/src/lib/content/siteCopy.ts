import { MARKETING_COPY } from '../../../../shared/marketingCopy';

export const siteCopy = {
  home: {
    hero: {
      eyebrow: 'AI-native productivity',
      headline: MARKETING_COPY.tagline,
      subhead:
        'An AI assistant works better when it lives beside your notes, tasks, saved pages, and files. sideBar keeps them together so help starts with context instead of a blank box.',
      primaryCta: 'Request Early Access',
      primaryHref: 'https://app.trysidebar.ai',
      secondaryCta: 'Read the Docs',
      secondaryHref: 'https://docs.trysidebar.ai',
      platforms: 'Available on iPhone, iPad, Mac, and web',
      media: {
        kind: 'image',
        src: '/screenshots/overview.png',
        alt: 'sideBar on iPad showing notes, chat, and saved work in one integrated workspace',
        width: 1366,
        height: 1024,
        loading: 'eager',
        fetchpriority: 'high',
        decoding: 'sync'
      }
    },
    thesis: {
      heading: 'Work and assistant, together.',
      body:
        'Most AI products still make you ferry context between a chat box and the rest of your tools. sideBar is built so your work and your assistant share the same place, which means help can begin from what is already in front of you.'
    },
    proofs: [
      {
        heading: 'Notes with a helping hand.',
        body:
          'Write in the same place you ask for help. sideBar can stay close to the note on screen, so drafting and refinement do not split into separate tools.',
        media: {
          kind: 'placeholder',
          label: 'iPhone Notes screenshot coming',
          frame: 'iphone',
          width: 430,
          height: 932
        }
      },
      {
        heading: 'Tasks, planned together.',
        body:
          'Plan with the assistant, then keep moving in the actual task list. The conversation and the plan belong to the same flow instead of two disconnected apps.',
        media: {
          kind: 'placeholder',
          label: 'iPhone Tasks screenshot coming',
          frame: 'iphone',
          width: 430,
          height: 932
        }
      },
      {
        heading: 'Save a page, ask about it later.',
        body:
          'Bring an article or reference page into sideBar once, then come back later to ask about it. The page stays available as part of your workspace.',
        media: {
          kind: 'image',
          src: '/screenshots/websites.png',
          alt: 'sideBar saved website workflow showing a page available for later questions',
          width: 1366,
          height: 1024
        }
      }
    ],
    identity: {
      heading: 'An assistant that grows with you.',
      body:
        'Once the practical proof is there, sideBar becomes more distinct. It has a point of view, can help you discover what it can actually do, and expands over time through installable skills.',
      points: [
        'Personality and onboarding that make the assistant feel like sideBar, not a generic wrapper.',
        "Self-aware guidance rooted in the product's real capabilities, so discovery starts from something concrete.",
        'Skills that extend the app with useful new behaviors as your workflow grows.'
        ],
      media: {
        kind: 'image',
        src: '/screenshots/skills-store.png',
        alt: 'sideBar skills store on iPad showing installable skills and product extensibility',
        width: 1366,
        height: 1024
      }
    },
    close: {
      headline: 'Keep sideBar open.',
      body:
        'The product is strongest when the assistant stays close to the rest of your work, ready to help without a reset every time.',
      primaryCta: 'Request Early Access',
      primaryHref: 'https://app.trysidebar.ai'
    }
  }
} as const;
