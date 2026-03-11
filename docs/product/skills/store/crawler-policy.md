---
title: Crawler Policy
summary: Analyse which web crawlers and AI systems can access a website's content.
tags: [skills, store, web, crawlers, ai-policy]
audience: user
surfaces: [app, website, internal-knowledge]
skill_id: web-crawler-policy
---

## What it does

Crawler Policy analyses the `robots.txt` and `llms.txt` files for any domain
and tells you exactly which crawlers can access it — with a particular focus
on AI crawlers from OpenAI, Anthropic, Google, and others. If you own a
website, this tells you whether AI companies can train on your content. If you
are researching a topic, it gives you insight into how a site handles
automated access.

Results are saved as a report in your Files.

## Actions

| Action | Description |
| --- | --- |
| Crawler policy check | Fetches and analyses the crawler policies for a domain, including AI and LLM crawler permissions, and saves a report to your Files |

## When sideBar uses it

When you ask sideBar to check crawler or AI access policies for a website:

- "Check the crawler policy for example.com"
- "Can AI companies train on content from my website?"
- "What does the robots.txt say for this domain?"
- "Which AI crawlers are blocked on this site?"

## Requirements

- **Tier:** Store (install from the Skills Store)
- **API key:** None required for standard analysis. An OpenAI API key is
  needed if you want an AI-generated strategic report alongside the raw
  analysis.

## How to install

1. Open the Skills Store and find Crawler Policy.
2. Tap **Install**. Add an OpenAI API key if you want the strategic report
   feature, or skip it for standard analysis.
3. The skill is ready immediately.

## What the report covers

- Which AI crawlers (GPTBot, ClaudeBot, Google-Extended, and others) are
  allowed or blocked
- Which traditional search crawlers have access
- Whether the site has an `llms.txt` file and what it says about AI training
  and inference permissions
- A breakdown by path if access is restricted to specific areas of the site

## Examples

> "Check the crawler policy for my website."

> "Is my blog accessible to AI training crawlers?"

> "What does the robots.txt say for the BBC website?"

> "Compare the crawler policies for these two domains."
