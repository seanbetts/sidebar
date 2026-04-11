---
name: web-search
description: Live web search operations for retrieving current information from external sources.
metadata:
  capabilities:
    reads: true
    writes: false
    network: true
    external_apis: true
---

# Web Search

Live web search operations for current information.

## Use Cases

- Look up recent news or current events
- Find up-to-date facts that are likely to change over time
- Gather supporting sources before answering a time-sensitive question

## Notes

- Web search is intended for fresh information rather than saved website content.
- Results should be summarized with source attribution when appropriate.
- This skill complements `web-save`, it does not replace the saved website workflow.
