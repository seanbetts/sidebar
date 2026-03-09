---
title: Privacy
summary: Common questions about how sideBar handles your data, AI training, encryption, location, and your rights.
tags: [faq, privacy, security]
audience: user
surfaces: [app, website, internal-knowledge]
---

## Does sideBar train AI models on my data?

No. sideBar does not use your data to train AI models, and never has. Your
notes, tasks, files, conversations, and memories are yours. They are used to
provide you with the service, not to improve any model.

## Do Anthropic, OpenAI, or Google train on my conversations?

No, not through sideBar. sideBar sends your content to AI providers via their
APIs, not through their consumer products. All three providers state in their
API terms that data submitted via the API is not used to train their models.
This is a meaningful distinction: when you use ChatGPT directly, Claude.ai
directly, or Gemini directly, different data practices may apply. Through
sideBar's API integration, your data is not used for training by any of them.

## Who can see my data?

sideBar staff have access only where necessary to operate, maintain, and secure
the service. Your content is also sent to whichever AI provider you have
configured when you use Chat. It goes only to that provider, not to all of them.
We do not sell your data to anyone.

## Where is my data stored?

Your data is stored using Supabase (database and authentication), Cloudflare R2
(file storage), and Cloudflare Pages (web hosting). Error and performance
diagnostics are processed via Sentry. All are contractually bound to handle your
data securely.

## Is my data encrypted?

Yes. Data is encrypted in transit and at rest across our infrastructure. API
keys you provide for AI providers and Store skills are encrypted before being
stored; only the last four characters are ever shown back to you.

## Does sideBar access my location?

Only if you grant permission. If you allow location access, sideBar uses your
precise device location to provide local weather and location context to your
assistant. If you do not grant permission, sideBar uses an approximate location
derived from your IP address for the same purpose. You can revoke location
permission at any time in your device settings.

## What data does sideBar share with third parties?

sideBar shares data only where necessary to operate the service: with
infrastructure providers (Supabase, Cloudflare, Sentry), with the AI provider
you have configured, and with any third-party services connected via Store
skills you have installed. We do not share data for advertising or sell it to
data brokers.

## How are API keys stored?

API keys you add in Settings (for your AI provider or for Store skills) are
encrypted before being stored. Only the last four characters are shown as
confirmation after saving. The full key is never displayed again and is never
transmitted in plaintext.

## Can I delete my account and data?

Yes. Email support@trysidebar.ai from your account email address to request
deletion. We may ask you to verify your identity first, and may retain limited
records where required for legal, security, or fraud-prevention reasons.

## Is sideBar suitable for sensitive or confidential information?

sideBar is designed with privacy as a priority and uses strong encryption and
a bring-your-own-key model. That said, any content you add to sideBar is sent
to your chosen AI provider when relevant during conversations. Review your AI
provider's API terms if you have specific requirements around confidential or
regulated data before using sideBar for that content.

## Where can I read the full privacy policy?

At [trysidebar.ai/privacy](https://trysidebar.ai/privacy). It covers data
collection, usage, retention, sharing, your rights, and how to contact us.
