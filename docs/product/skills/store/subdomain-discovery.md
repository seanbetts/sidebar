---
title: Subdomain Discovery
summary: Map out all the public subdomains associated with any domain.
tags: [skills, store, web, domains, research]
audience: user
surfaces: [app, website, internal-knowledge]
---

## What it does

Subdomain Discovery maps out the public web presence of any domain by finding
all its associated subdomains. It combines three techniques — DNS probing,
certificate transparency logs, and sitemap parsing — to build a comprehensive
picture of a site's digital footprint. Results are filtered to focus on
consumer-facing properties, removing internal, staging, and redirect-only
subdomains automatically.

This is useful for researching an organisation's web presence, preparing for
a security audit, or feeding into the [Crawler Policy](/skills/store/crawler-policy)
skill to analyse policies across all subdomains at once.

## Actions

| Action | Description |
| --- | --- |
| Discover subdomains | Finds all public subdomains for a domain using DNS probing, certificate transparency logs, and sitemap parsing, and returns a filtered list |

## When sideBar uses it

When you ask sideBar to map or research a domain's subdomains:

- "Find all the subdomains for example.com"
- "What web properties does this company have?"
- "Map the digital footprint of this domain"

## Requirements

- **Tier:** Store (install from the Skills Store)
- **API key:** None required

## How to install

1. Open the Skills Store and find Subdomain Discovery.
2. Tap **Install**.
3. The skill is ready immediately.

## How it works

Discovery runs three methods in parallel and merges the results:

- **DNS probing**: tests over 100 common subdomain names (www, api, docs, blog, shop, and more)
- **Certificate transparency**: queries public certificate logs to find subdomains from historical SSL certificates
- **Sitemap parsing**: extracts domain references from the site's sitemap and robots.txt

Redirect-only subdomains and internal properties (dev, staging, test environments) are filtered out automatically. Results are capped at 30 domains, prioritising high-value consumer-facing properties.

## Examples

> "Find all the subdomains for apple.com."

> "What web properties does Stripe have?"

> "Map the digital footprint of this company's domain."
