# CLI Tools and Troubleshooting

Read when validating a flag file with the `goff` CLI, testing evaluation against a local relay, or diagnosing flags that evaluate wrongly, providers that fail to connect, or configuration that does not update.

## CLI Tools

### Validate Configuration

```bash
# Install CLI
go install github.com/thomaspoignant/go-feature-flag/cmd/goff@latest

# Validate flag file
goff lint --config flags.goff.yaml

# Output format
goff lint --config flags.goff.yaml --format json
```

### Testing Flags Locally

```bash
# Start relay in foreground
docker run -p 1031:1031 -p 1032:1032 \
  -v $(pwd)/flags.goff.yaml:/goff/flags.yaml:ro \
  -e RETRIEVER_KIND=file \
  -e RETRIEVER_PATH=/goff/flags.yaml \
  gofeatureflag/go-feature-flag:latest

# Test flag evaluation
curl -X POST http://localhost:1031/v1/feature/new-feature/eval \
  -H "Content-Type: application/json" \
  -d '{"evaluationContext": {"targetingKey": "user-123"}}'
```

## Troubleshooting

### Flag Not Evaluating Correctly

```bash
# Check relay logs
docker logs goff-relay

# Test evaluation directly
curl -X POST http://localhost:1031/v1/feature/my-flag/eval \
  -H "Content-Type: application/json" \
  -d '{"evaluationContext": {"targetingKey": "test", "email": "test@example.com"}}'
```

### Provider Connection Issues

```typescript
// Check provider initialization
const provider = new GoFeatureFlagProvider({
  endpoint: process.env.GOFF_RELAY_URL,
  timeout: 5000, // Increase timeout
});

// Handle events
provider.on('PROVIDER_READY', () => console.log('Provider ready'));
provider.on('PROVIDER_ERROR', (e) => console.error('Provider error', e));
```

### Configuration Not Updating

```bash
# Check polling interval
POLLING_INTERVAL_MS=10000  # 10 seconds

# Verify file is readable
docker exec goff-relay cat /goff/flags.yaml

# Check retriever status
curl http://localhost:1032/info
```
