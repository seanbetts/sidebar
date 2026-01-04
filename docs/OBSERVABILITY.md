# Observability Dashboards

This document outlines the baseline dashboards to create for sideBar in Grafana/Sentry.

## Prometheus / Grafana

### API Health Dashboard
- Request rate (RPS)
- p50/p95/p99 latency
- 4xx/5xx error rates
- Slow endpoints (top 10 by p95)

### Chat Streaming Dashboard
- Time to first token
- Stream duration
- Stream error rate
- Active streams count

### Ingestion Pipeline Dashboard
- Jobs by status (queued/running/failed/succeeded)
- Processing stage durations
- Worker throughput (files/hour)
- Failure reasons (top error codes)

### Storage Dashboard
- R2 request rate / latency
- Storage errors
- Bytes uploaded/downloaded

## Sentry

### Error Overview
- Error count by release
- Top exceptions (last 24h)
- New vs. regressed issues

### Performance
- Slow transactions (p95)
- Endpoint-level traces
- Frontend performance (page load, route changes)

## Notes

- Start with API Health + Ingestion dashboards before expanding.
- Align panel names with service owners (backend, ingestion, frontend).
