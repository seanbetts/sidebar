"""Prometheus metrics for monitoring."""
from __future__ import annotations

from prometheus_client import Counter, Histogram, Gauge

# Request metrics
http_requests_total = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)

http_request_duration_seconds = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration",
    ["method", "endpoint"],
)

# Chat metrics
chat_messages_total = Counter(
    "chat_messages_total",
    "Total chat messages sent",
)

chat_streaming_duration_seconds = Histogram(
    "chat_streaming_duration_seconds",
    "Duration of chat streaming responses",
)

# Tool execution metrics
tool_executions_total = Counter(
    "tool_executions_total",
    "Total tool executions",
    ["skill_id", "status"],
)

tool_execution_duration_seconds = Histogram(
    "tool_execution_duration_seconds",
    "Tool execution duration",
    ["skill_id"],
)

# Database metrics
db_connections_active = Gauge(
    "db_connections_active",
    "Active database connections",
)

# Storage metrics
storage_operations_total = Counter(
    "storage_operations_total",
    "Total storage operations",
    ["operation", "status"],
)

