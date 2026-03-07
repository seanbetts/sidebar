# Chat Request Budgeting Runbook

## Purpose
- Explain the budget-related signals emitted by the chat runtime.
- Help diagnose trims, compactions, and final overflow failures without reading raw prompt content.

## Signals
- Metric: `chat_request_budget_events_total{stage,outcome,dominant_component}`
- Structured log: `Chat request budget decision (...)`

## Stages
- `prepared`: first prepared request after request assembly and history trimming
- `compaction_retry`: prepared request rebuilt after persisted conversation compaction
- `overflow`: final failure after trimming and any compaction retry

## Outcomes
- `within_budget`: the prepared request fit after trimming and/or compaction
- `overflow`: the request still exceeded the model input budget

## Dominant Components
- `conversation_history`: older replayed chat history is the largest input contributor
- `system_prompt`: rebuilt per-turn operating context is the largest contributor
- `bootstrap_history`: hidden first-turn bootstrap history is the largest contributor
- `current_message`: the current user turn is the largest contributor
- `tool_schema`: provider-shaped tool definitions are the largest contributor

## User-Facing Errors
- History-dominant overflow:
  `Chat request is too large even after trimming conversation history. Start a new conversation or reduce context and try again.`
- Non-history overflow:
  `Message context is too large for this chat request. Remove some attachments or close open items and try again.`

## Operator Guidance
- If `dominant_component=conversation_history` at `overflow`, check whether the conversation was compacted and whether the remaining recent tail is still too large. Starting a new conversation is the expected recovery path.
- If `dominant_component` is `system_prompt`, `bootstrap_history`, or `current_message`, inspect open context and attachment-heavy requests first. These overflows are usually caused by live context rather than saved chat history.
- If `dominant_component=tool_schema`, review enabled skills and provider tool-shaping changes. Tool schema overhead should be stable for a given provider and skill set.
- If `prepared` events frequently show `within_budget` with `trimming_applied=true`, the system is recovering correctly but operating close to the model limit. That is a tuning signal, not an incident by itself.

## What Not To Do
- Do not log or copy raw prompt text into tickets.
- Do not delete stored conversation messages to relieve pressure; use compaction or start a fresh conversation.
- Do not treat a single `prepared` trim event as a failure if the final request still fit.
