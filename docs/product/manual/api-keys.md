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

## Getting an Anthropic API Key

1. Go to [console.anthropic.com](https://console.anthropic.com) and sign in
   or create an account.
2. Open the **API Keys** section from the left sidebar.
3. Click **Create Key**, give it a name, and click **Create Key** to confirm.
4. Copy the key immediately — it is only shown once.
5. Add a payment method under **Billing** if you have not already done so.
   Anthropic requires a payment method before API keys can be used.

## Getting an OpenAI API Key

1. Go to [platform.openai.com](https://platform.openai.com) and sign in or
   create an account.
2. Click your profile icon in the top right and select **API keys**.
3. Click **Create new secret key**, give it a name, and confirm.
4. Copy the key immediately — it is only shown once.
5. Make sure your account has credits. Go to **Settings → Billing** to add a
   payment method or purchase a credit pack if needed.

## Getting a Google API Key

1. Go to [aistudio.google.com](https://aistudio.google.com) and sign in with
   your Google account.
2. Click **Get API key** in the left sidebar.
3. Click **Create API key** and select or create a Google Cloud project.
4. Copy the key.
5. Google AI Studio provides free tier access, with pay-as-you-go available
   once you link a Google Cloud billing account.

## Adding Your Key to sideBar

1. Open **Settings → sideBar**.
2. Select your provider under **AI Provider**.
3. Paste your API key into the field and save.

Only the last four characters of your key are shown after saving. The full
key is never displayed again. To update your key, tap the field and paste a
new one.

## Troubleshooting

If sideBar shows an API error after you add your key, the most common causes
are:

- **Invalid key**: make sure you copied the full key without extra spaces
- **No credits or payment method**: check your billing settings with your
  provider
- **Rate limit**: your provider account may have usage limits. Check your
  provider's dashboard for details

See [Troubleshooting](/manual/troubleshooting) for more.
