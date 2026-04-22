import { MARKETING_COPY } from '../../../../shared/marketingCopy';

export const siteCopy = {
  home: {
    hero: {
      headline: MARKETING_COPY.tagline,
      subhead: MARKETING_COPY.subtitle,
      primaryCta: 'Join Early Access List',
      primaryHref: '/early-access',
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
          'Ask for help where your notes, tasks, and saved pages already live.',
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
          'Write in the same place you ask for assisstance.',
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
          'Plan with the assistant, then keep moving through your task list.',
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
          'Bring an article or reference page into sideBar once, then come back later to ask about it.',
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
        'Get to know sideBar faster. It can introduce itself properly, show you what is available, and grow with you through installable skills.',
      media: {
        kind: 'image',
        src: '/screenshots/skills-store-iphone.png',
        alt: 'sideBar skills store on iPhone showing installable skills and product extensibility',
        frame: 'iphone',
        width: 430,
        height: 932
      }
    }
  }
} as const;
