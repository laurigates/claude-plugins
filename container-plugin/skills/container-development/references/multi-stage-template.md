# Multi-Stage Build Template

```dockerfile
# Build stage - includes all build tools
FROM <language>:<version> AS builder
WORKDIR /app

# Copy dependency manifests first (better caching)
COPY package.json package-lock.json ./  # or go.mod, requirements.txt, etc.

# Install dependencies
RUN <install-command>

# Copy source code
COPY . .

# Build application
RUN <build-command>

# Runtime stage - minimal
FROM <minimal-base>
WORKDIR /app

# Create non-root user
RUN addgroup --gid 1001 appgroup && \
    adduser --uid 1001 --gid 1001 --disabled-password appuser

# Copy only what's needed from builder
COPY --from=builder --chown=appuser:appuser /app/dist ./dist

USER appuser
EXPOSE <port>

HEALTHCHECK --interval=30s CMD <health-check-command>

CMD [<start-command>]
```
