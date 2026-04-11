---
title: Web Search
summary: Search the live web for current information, recent news, and real-time facts.
tags: [skills, web, search]
audience: user
surfaces: [app, website, internal-knowledge]
skill_id: web-search
---

## What it does

Web Search gives sideBar access to the live web. When your question requires
current or real-time information, such as news, recent releases, live prices,
or today's weather outside your location, sideBar searches the web and incorporates the
results into its response, citing its sources.

## Actions

| Action | Description |
| --- | --- |
| Search the web | Searches the live web and incorporates results and cited sources into the response |

## When sideBar uses it

sideBar uses Web Search automatically when it detects your question needs
information it cannot answer from what it already knows. Common triggers:

- Questions about recent events or news ("What happened with X this week?")
- Requests for current data ("What is the latest version of Y?")
- Fact-checking or verifying something time-sensitive
- Research tasks where up-to-date sources matter

You don't need to ask sideBar to search, it decides when a search would
improve the response.

## Requirements

- **Tier:** Standard (included, no installation needed)
- **Provider support:** Anthropic, OpenAI, and Google on supported chat models
- **API key:** Uses the key for your selected AI provider

If you are using sideBar's default hosted path, there is no extra setup.
If you choose your own provider in Settings, Web Search uses that provider's
web search capability when the selected model supports it.

## How to enable

Web Search is enabled by default. If you have turned it off and want to
re-enable it, go to **Settings → Skills** and toggle Web Search on.

If Web Search is enabled but your selected provider model does not support it,
sideBar falls back to its normal non-search response path.

## Examples

> "What's in the news today?"

> "What are the best-reviewed noise cancelling headphones right now?"

> "What's the latest version of Python?"
