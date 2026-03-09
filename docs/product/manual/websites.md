---
title: Websites
summary: Save web pages to read later, browse them offline, and give sideBar access to work with the content alongside you.
tags: [manual, websites, reading]
audience: user
surfaces: [app, website, internal-knowledge]
---

{/* TODO: screenshot — websites.png: Websites list with a few saved pages (iPad landscape) */}
<Frame>
  {/* TODO: alt text — replace with a rich, specific description of what's shown (for screen readers and AI crawlers) */}
  <img src="/assets/screenshots/websites.png" alt="sideBar saved websites list" />
</Frame>

Websites is a read-it-later service built into sideBar. Save pages you want to
read, and they're stored in full, ready to read offline and available to
sideBar so you can work with the content together: summarise it, ask questions
about it, take notes, or dig deeper with further research.

## Saving a Page

There are three ways to save a web page:

- **Share sheet**: tap the share button in any app and choose sideBar to save
  the current page instantly. See [Widgets & Extensions](/manual/extensions)
  to enable it.
- **Safari extension**: tap the sideBar button in your browser toolbar to
  save the page without leaving it. See [Widgets & Extensions](/manual/extensions)
  to set it up.
- **Manual URL entry**: tap **+** in the Websites tab and paste or type the
  URL directly.

Once saved, sideBar fetches the page and automatically extracts the title,
domain, favicon, full page content, and estimated reading time. If a
publication date is detectable, that's saved and displayed too. You can rename
the title any time after saving.

## Supported Sites

sideBar has custom parsers for a range of popular sites, which means you get
cleaner content and richer extraction than a generic web fetch provides.

**Enhanced extraction** — these sites get meaningfully more than a standard
page save:

- **YouTube**: full transcript extraction alongside the video title and
  metadata. See [YouTube Support](#youtube-support) below.
- **Twitter / X**: tweet content saved with the author name, handle, and
  publication date.
- **Substack**: full article content fetched via the Substack API, not just
  the preview shown to non-subscribers.
- **GitHub**: clean README extraction with badges, avatars, and decorative
  elements stripped out.
- **Harvard Business Review**: full article body reconstructed from
  structured data, bypassing the HTML layout.
- **Apple News**: redirect links are automatically unwrapped to fetch the
  original publisher content.

**Optimised reading** — these sites have noise stripped out for a cleaner
reading and chat experience:

- The Verge, Wired, Gizmodo, OpenAI, blog.google, Steam Community

**Paywalled sites** — sideBar can save pages from paywalled publications, but
if you are not a subscriber the content will be truncated to whatever the site
makes available publicly. This applies to sites including the New York Times,
Wall Street Journal, Financial Times, The Economist, and Bloomberg. sideBar
will flag when a saved page appears to be paywalled.

For sites not listed here, sideBar uses a general-purpose parser that works
well across most publications and blogs.

## YouTube Support

{/* TODO: screenshot — websites-youtube.png: A saved YouTube video showing transcript (iPad landscape) */}
<Frame>
  {/* TODO: alt text — replace with a rich, specific description of what's shown (for screen readers and AI crawlers) */}
  <img src="/assets/screenshots/websites-youtube.png" alt="sideBar YouTube transcript view" />
</Frame>

Saving a YouTube URL triggers automatic transcript extraction. The status
progresses through three stages, **queued**, **processing**, then **ready**.
Once ready, the transcript is stored alongside the video's title and metadata
and is available to sideBar for summarising, quoting, or answering
questions about the video.

If extraction fails, the page is still saved and you'll see an error status in
the transcript field.

## Managing Your Web Pages

- **Pin** important pages to keep them at the top of your list.
- **Archive** pages you're finished with. Archived pages aren't deleted, you
  can always find them again.
- **Rename** any page by tapping its title.
- **Delete** a page to remove it permanently.
- **Search** across your saved pages by title, domain, or page content. A
  useful way to find something when you can't remember where you saved it.

You can also swipe right on any page to archive or unarchive it, or swipe left
to delete it.

## Reading a Saved Page

Open any saved page to see its full content. Tap the page title to open the
original URL in your default browser. Text is selectable if you want to copy
a passage.

## Working with sideBar on a Page

With a page open, sideBar can see the full content and work with you on it.
Ask it to summarise the article, explain a concept, pull out key points, draft
notes, or find related information. See [Chat](/manual/chat) for more on how
sideBar uses what you have open.

## Export and Sharing

From any saved page you can:

- **Export as markdown**: saves a `.md` file you can open in any text editor.
- **Copy the title**, **URL**, or **full markdown content** with a single tap,
  handy for pasting into a note, message, or document.
