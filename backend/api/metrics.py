"""Prometheus metrics for monitoring."""

from __future__ import annotations

from prometheus_client import Counter, Gauge, Histogram

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

chat_first_token_latency_seconds = Histogram(
    "chat_first_token_latency_seconds",
    "Latency from user send to first token",
)

chat_sse_connect_seconds = Histogram(
    "chat_sse_connect_seconds",
    "Latency from stream start to first SSE event",
)

chat_stream_errors_total = Counter(
    "chat_stream_errors_total",
    "Total chat streaming errors",
    ["type"],
)

chat_tool_duration_seconds = Histogram(
    "chat_tool_duration_seconds",
    "Client tool execution duration",
    ["tool_name", "status"],
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

# Web Vitals metrics
web_vitals_observations_total = Counter(
    "web_vitals_observations_total",
    "Total Web Vitals observations",
    ["name", "rating"],
)

web_vitals_value = Histogram(
    "web_vitals_value",
    "Web Vitals measurement values",
    ["name", "rating"],
)
