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
providers at any time from **Settings > sideBar** without losing any of your
content or memories.

## Getting an API Key

Each provider has their own dashboard for creating API keys. Pick your
provider below for step-by-step instructions.

### Anthropic

1. Go to [platform.claude.com](https://platform.claude.com) and sign up or
   sign in.
2. Open **Settings > Billing** and add a payment method.
3. Go to **Settings > API Keys**.
4. Click **Create Key**, give it a name (e.g. "sideBar"), and click
   **Create Key** to confirm.
5. Copy the key (it starts with `sk-ant-api03-`). This is the only time it
   will be shown.

For more details, see the
[Anthropic API docs](https://platform.claude.com/docs/en/api/getting-started).

### OpenAI

1. Go to [platform.openai.com](https://platform.openai.com) and sign up or
   sign in.
2. Open **Settings > Billing** and add a payment method.
3. Click **API keys** in the left sidebar.
4. Click **Create new secret key**, give it a name (e.g. "sideBar"), and
   click **Create secret key**.
5. Copy the key (it starts with `sk-proj-`). This is the only time it will
   be shown.

For more details, see the
[OpenAI API docs](https://platform.openai.com/docs/quickstart).

### Google

1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
   and sign in with your Google account.
2. Click **Get API key** if you are not already on the API keys page.
3. Click **Create a Gemini API Key** and select a Google Cloud project (or
   let Google create a default one for you).
4. Copy the key (it starts with `AIza`). Unlike Anthropic and OpenAI, you
   can view this key again later from the same page.

The Gemini API includes a free tier. For usage beyond the free tier, you may
need to enable billing on the linked Google Cloud project.

For more details, see the
[Gemini API docs](https://ai.google.dev/gemini-api/docs/api-key).

## Adding Your Key to sideBar

1. Open **Settings > sideBar**.
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
  provider, as most providers require a payment method before keys can be used
- **Key revoked or expired**: generate a new key from your provider's dashboard
  and update it in **Settings > sideBar**

See [Troubleshooting](/manual/troubleshooting) for more.
