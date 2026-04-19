import { MARKETING_COPY } from '../../../../shared/marketingCopy';

export const siteCopy = {
  home: {
    hero: {
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
        frame: 'ipad',
        src: '/screenshots/welcome-ipad.png',
        alt: 'sideBar on iPad showing notes, chat, and saved work in one integrated workspace',
        width: 1366,
        height: 1024,
        loading: 'eager',
        fetchpriority: 'high',
        decoding: 'sync'
      }
    },
    proofs: [
      {
        heading: 'Chat that starts from your work.',
        reverse: true,
        body:
          'Ask for help where your notes, tasks, and saved pages already live. sideBar can respond from the context in front of you instead of making every conversation start from zero.',
        media: {
          kind: 'image',
          src: '/screenshots/chat-iphone.png',
          alt: 'sideBar chat on iPhone with assistant responses grounded in the surrounding workspace',
          frame: 'iphone',
          width: 430,
          height: 932
        }
      },
      {
        heading: 'Notes with a helping hand.',
        reverse: false,
        body:
          'Write in the same place you ask for help. sideBar can stay close to the note on screen, so drafting and refinement do not split into separate tools.',
        media: {
          kind: 'image',
          src: '/screenshots/notes-ipad.png',
          alt: 'sideBar notes on iPad with writing and assistant help in the same workspace',
          frame: 'ipad',
          width: 1366,
          height: 1024
        }
      },
      {
        heading: 'Tasks, planned together.',
        reverse: true,
        body:
          'Plan with the assistant, then keep moving in the actual task list. The conversation and the plan belong to the same flow instead of two disconnected apps.',
        media: {
          kind: 'image',
          src: '/screenshots/tasks-iphone.png',
          alt: 'sideBar tasks on iPhone with assistant guidance alongside the task list',
          frame: 'iphone',
          width: 430,
          height: 932
        }
      },
      {
        heading: 'Save a page, ask about it later.',
        reverse: false,
        body:
          'Bring an article or reference page into sideBar once, then come back later to ask about it. The page stays available as part of your workspace.',
        media: {
          kind: 'image',
          src: '/screenshots/websites-ipad.png',
          alt: 'sideBar websites on iPad with a saved page available for later questions',
          frame: 'ipad',
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
        src: '/screenshots/skills-store-iphone.png',
        alt: 'sideBar skills store on iPhone showing installable skills and product extensibility',
        frame: 'iphone',
        width: 430,
        height: 932
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
