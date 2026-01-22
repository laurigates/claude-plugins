---
model: haiku
created: 2026-01-01
modified: 2026-01-01
reviewed: 2026-01-01
name: HTTP Load Testing
description: HTTP load testing and stress testing with oha - real-time TUI, latency correction for coordinated omission, and HTTP/2-3 support. Includes comparison with wrk, vegeta, and hey.
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
---

# HTTP Load Testing

Expert knowledge for HTTP load testing using oha, a Rust-based load generator with real-time TUI visualization and proper latency measurement.

## Core Concepts

### Coordinated Omission Problem

Traditional load testers measure only the time from request send to response received. This misses queuing delays when the server slows down, leading to **optimistic latency numbers**.

**Example**: If your target is 100 RPS but the server can only handle 50 RPS:
- **Without correction**: Measures only successful request latencies (looks good)
- **With correction**: Accounts for requests that couldn't be sent on schedule (reveals true user experience)

oha addresses this with `--latency-correction` (enabled by default).

### Latency Percentiles

| Percentile | Meaning | Use Case |
|------------|---------|----------|
| p50 (median) | Half of requests faster | Typical user experience |
| p90 | 90% of requests faster | Most users' experience |
| p99 | 99% of requests faster | Tail latency, SLA targets |
| p99.9 | 99.9% of requests faster | Worst-case scenarios |

**Rule of thumb**: Focus on p99 for SLAs. A 100ms p50 with 2s p99 indicates serious tail latency issues.

## Why oha

| Feature | oha | wrk | vegeta | hey |
|---------|-----|-----|--------|-----|
| Latency correction | Yes (default) | No | No | No |
| Real-time TUI | Yes | No | No | No |
| HTTP/2 | Yes | No | Yes | Yes |
| HTTP/3 (experimental) | Yes | No | No | No |
| Scripting | No | Lua | No | No |
| CI-friendly output | Yes (JSON) | Limited | Yes | Yes |
| Active maintenance | Yes | Limited | Yes | No |

## Installation

```bash
# macOS
brew install oha

# Cargo (any platform)
cargo install oha

# Verify
oha --version
```

## Essential Commands

### Basic Load Test

```bash
# 200 requests with 50 concurrent connections
oha -n 200 -c 50 https://api.example.com/health

# Run for 30 seconds
oha -z 30s -c 50 https://api.example.com/health

# Target specific requests per second (QPS)
oha -q 100 -z 30s https://api.example.com/health
```

### Request Configuration

```bash
# POST with JSON body
oha -m POST -H "Content-Type: application/json" -d '{"key":"value"}' https://api.example.com/data

# Custom headers
oha -H "Authorization: Bearer TOKEN" -H "X-Custom: value" https://api.example.com/protected

# Request body from file
oha -m POST -D @request.json https://api.example.com/data
```

### Connection Settings

```bash
# HTTP/2
oha --http-version 2 https://api.example.com/health

# Disable keep-alive (new connection per request)
oha --disable-keepalive https://api.example.com/health

# Connection timeout
oha --timeout 10s https://api.example.com/slow-endpoint
```

### TUI and Output Control

```bash
# Disable TUI (for scripts/CI)
oha --no-tui -n 1000 https://api.example.com/health

# JSON output for parsing
oha --no-tui -j -n 1000 https://api.example.com/health

# Disable latency correction (compare with corrected)
oha --no-tui --disable-latency-correction -n 1000 https://api.example.com/health
```

## Common Patterns

### Quick Health Check

```bash
# Fast sanity check - 100 requests, 10 connections
oha -n 100 -c 10 --no-tui https://api.example.com/health
```

### Sustained Load Test

```bash
# 5 minutes at 100 RPS with 50 connections
oha -z 5m -q 100 -c 50 https://api.example.com/endpoint
```

### Find Breaking Point

```bash
# Gradually increase load
for qps in 50 100 200 400 800; do
  echo "Testing at $qps RPS..."
  oha --no-tui -j -z 30s -q $qps https://api.example.com/health | jq '.summary'
done
```

### Compare With/Without Latency Correction

```bash
# Shows the coordinated omission effect
echo "With correction:"
oha --no-tui -z 30s -q 500 https://api.example.com/health

echo "Without correction:"
oha --no-tui --disable-latency-correction -z 30s -q 500 https://api.example.com/health
```

### POST Endpoint Load Test

```bash
oha -m POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"user_id": 123, "action": "test"}' \
  -z 60s -c 20 \
  https://api.example.com/events
```

## Interpreting Results

### TUI Display

The real-time TUI shows:
- Request rate (current/target)
- Latency histogram
- Status code distribution
- Error rate

### JSON Output Fields

```bash
oha --no-tui -j -n 1000 https://api.example.com/health | jq '.'
```

Key fields:
- `.summary.successRate` - Percentage of 2xx responses
- `.summary.total` - Total requests sent
- `.summary.slowest` - Maximum latency
- `.summary.fastest` - Minimum latency
- `.summary.average` - Mean latency
- `.latencyDistribution` - Percentile breakdown (p50, p90, p99, etc.)
- `.statusCodeDistribution` - Count per HTTP status code

### What to Look For

| Metric | Good | Concerning | Critical |
|--------|------|------------|----------|
| Success rate | >99.9% | 99-99.9% | <99% |
| p99/p50 ratio | <5x | 5-10x | >10x |
| Error rate | 0% | <1% | >1% |
| p99 latency | <SLA target | Near SLA | >SLA |

## Alternative Tools

### wrk/wrk2

High-throughput benchmarking with Lua scripting.

```bash
# Basic test
wrk -t12 -c400 -d30s https://api.example.com/health

# With Lua script for custom requests
wrk -t12 -c400 -d30s -s script.lua https://api.example.com/
```

**Use when**: Need Lua scripting for complex request patterns or maximum throughput testing.

**Limitation**: Does not handle coordinated omission.

### vegeta

Go-based load tester with attack/report workflow.

```bash
# Generate constant load
echo "GET https://api.example.com/health" | vegeta attack -rate=100/s -duration=30s | vegeta report

# JSON output
echo "GET https://api.example.com/health" | vegeta attack -rate=100/s -duration=30s | vegeta encode --to json

# Plot latencies
echo "GET https://api.example.com/health" | vegeta attack -rate=100/s -duration=30s | vegeta plot > plot.html
```

**Use when**: Need CI-friendly pipeline workflow or latency plots.

**Limitation**: Does not correct for coordinated omission.

### hey

Simple HTTP load generator (successor to ab).

```bash
# 10000 requests, 100 concurrent
hey -n 10000 -c 100 https://api.example.com/health

# Rate limited
hey -n 10000 -c 100 -q 50 https://api.example.com/health
```

**Use when**: Quick ad-hoc testing, familiar with ab.

**Limitation**: Unmaintained, no coordinated omission handling.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick test | `oha --no-tui -n 100 -c 10 $URL` |
| CI pipeline | `oha --no-tui -j -z 30s -q 100 $URL` |
| JSON parsing | `oha --no-tui -j $URL \| jq '.summary'` |
| Success rate | `oha --no-tui -j $URL \| jq '.summary.successRate'` |
| Latency p99 | `oha --no-tui -j $URL \| jq '.latencyDistribution."99"'` |
| Fail on errors | `oha --no-tui -j $URL \| jq -e '.summary.successRate > 99'` |

## Quick Reference

### Core Flags

| Flag | Description | Default |
|------|-------------|---------|
| `-n, --number` | Total requests to send | 200 |
| `-c, --connections` | Concurrent connections | 50 |
| `-z, --duration` | Test duration (e.g., 30s, 5m) | - |
| `-q, --query-per-second` | Target QPS rate limit | unlimited |

### Request Flags

| Flag | Description |
|------|-------------|
| `-m, --method` | HTTP method (GET, POST, etc.) |
| `-H, --header` | Add header (repeatable) |
| `-d, --data` | Request body |
| `-D, --data-file` | Request body from file |

### Output Flags

| Flag | Description |
|------|-------------|
| `--no-tui` | Disable real-time TUI |
| `-j, --json` | JSON output (requires --no-tui) |
| `--disable-latency-correction` | Disable coordinated omission fix |

### Connection Flags

| Flag | Description |
|------|-------------|
| `--http-version` | 1.0, 1.1, or 2 |
| `--disable-keepalive` | New connection per request |
| `--timeout` | Request timeout |
| `--connect-timeout` | Connection timeout |

## Resources

- **oha repository**: https://github.com/hatoo/oha
- **Coordinated Omission explained**: https://www.scylladb.com/2021/04/22/on-coordinated-omission/
- **wrk2 paper**: https://github.com/giltene/wrk2 (discusses latency measurement)
