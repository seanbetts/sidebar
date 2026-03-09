---
title: API Keys
summary: How to get an API key from Anthropic, OpenAI, or Google and connect it to sideBar.
tags: [manual, api-keys, setup]
audience: user
surfaces: [app, website, internal-knowledge]
---

sideBar uses your own API key to connect to your chosen AI provider. This
means your usage is billed directly to you by the provider, at their standard
rates. sideBar stores your key encrypted and never displays it in full after
you save it.

## Choosing a Provider

sideBar supports three providers: **Anthropic**, **OpenAI**, and **Google**.
All three work with sideBar's core features. The best choice depends on which
you already have an account with, or which model you prefer. You can switch
providers at any time from **Settings → sideBar** without losing any of your
content or memories.

## Getting an API Key

Each provider has their own dashboard for creating API keys. The steps may
vary as these dashboards change over time, but the general flow is the same:
create an account, navigate to the API keys section, generate a new key, and
copy it before closing the page. Keys are typically only shown once.

You will also need to ensure your account has a payment method or credits
attached before the key will work.

- **Anthropic**: [console.anthropic.com](https://console.anthropic.com)
- **OpenAI**: [platform.openai.com](https://platform.openai.com)
- **Google**: [aistudio.google.com](https://aistudio.google.com)

## Adding Your Key to sideBar

1. Open **Settings → sideBar**.
2. Select your provider under **AI Provider**.
3. Paste your API key into the field and save.

Only the last four characters of your key are shown after saving. The full
key is never displayed again. To update your key, tap the field and paste a
new one.

## Troubleshooting

If sideBar shows an error after you add your key, the most common causes are:

- **Key copied incorrectly**: make sure you copied the full key without extra
  spaces or missing characters
- **No credits or payment method**: check your billing settings with your
  provider — most providers require a payment method before keys can be used
- **Key revoked or expired**: generate a new key from your provider's dashboard
  and update it in **Settings → sideBar**

See [Troubleshooting](/manual/troubleshooting) for more.
