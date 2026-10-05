# Relay Proxy Configuration

Read when deploying or configuring the GOFF relay proxy locally: the Docker Compose service definition and the full retriever/polling/server environment variables.

## Docker Compose (Development)

```yaml
# docker-compose.yaml
services:
  goff-relay:
    image: gofeatureflag/go-feature-flag:latest
    ports:
      - "1031:1031"  # API
      - "1032:1032"  # Health/metrics
    volumes:
      - ./flags.goff.yaml:/goff/flags.yaml:ro
    environment:
      # Retriever configuration
      - RETRIEVER_KIND=file
      - RETRIEVER_PATH=/goff/flags.yaml

      # Polling interval (ms)
      - POLLING_INTERVAL_MS=10000

      # Logging
      - LOG_LEVEL=info
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:1032/health"]
      interval: 10s
      timeout: 5s
      retries: 3
```

## Environment Variables

```bash
# Retriever (choose one)
RETRIEVER_KIND=file|s3|http|github|gitlab|googlecloud|azureblob|k8s

# File retriever
RETRIEVER_PATH=/path/to/flags.yaml

# S3 retriever
RETRIEVER_BUCKET=my-bucket
RETRIEVER_ITEM=flags/production.yaml
AWS_REGION=us-east-1

# GitHub retriever
RETRIEVER_REPOSITORY_SLUG=owner/repo
RETRIEVER_FILE_PATH=flags/production.yaml
RETRIEVER_BRANCH=main
GITHUB_TOKEN=ghp_xxxx

# HTTP retriever
RETRIEVER_URL=https://api.example.com/flags.yaml
RETRIEVER_HEADERS=Authorization=Bearer xxx

# Polling
POLLING_INTERVAL_MS=30000

# Server
HTTP_PORT=1031
ADMIN_PORT=1032
LOG_LEVEL=info|debug|warn|error
```
