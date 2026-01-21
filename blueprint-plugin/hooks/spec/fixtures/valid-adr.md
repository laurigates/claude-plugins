---
status: Accepted
created: 2025-01-20
modified: 2025-01-20
domain: authentication
---

# ADR 0001: Use JWT for Authentication

## Context

We need to implement user authentication for the application.

## Decision

We will use JWT (JSON Web Tokens) for authentication.

## Consequences

- Stateless authentication
- Tokens can be validated without database lookup
- Must handle token expiration and refresh

## Options Considered

1. **JWT** - Stateless, scalable
2. **Session cookies** - Traditional, requires session storage
3. **OAuth2 only** - Requires third-party provider

## Related ADRs

- ADR 0002: Token Refresh Strategy
