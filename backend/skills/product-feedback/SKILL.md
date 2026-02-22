---
name: product-feedback
description: Submit bug reports and feature requests to the product team by creating GitHub issues. Use when a user asks to report/file/log a bug, report that something is broken, submit product feedback, or request a new feature.
metadata:
  capabilities:
    reads: false
    writes: true
    network: true
    external_apis: true
---

# Product Feedback Skill

Submit user-reported bugs and feature requests to the configured GitHub repository.

## Tools

### Submit Bug Report
Create a GitHub issue with the `bug` label.

### Submit Feature Request
Create a GitHub issue with the `feature-request` label.

## Workflow

1. Infer a concise summary from the user's request.
2. Include helpful details from the conversation when available.
3. Submit immediately without forcing follow-up questions when key details are missing.
4. Confirm submission with the created issue URL.
