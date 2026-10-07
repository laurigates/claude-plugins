# Ticket drafting: complete examples

## Complete Examples

### Feature Request

```markdown
## What

Add dark mode support to the web interface. This provides an alternative
color scheme that reduces eye strain in low-light conditions. Related to
[#789](https://github.com/owner/repo/issues/789).

Reference: [CSS color-scheme](https://developer.mozilla.org/en-US/docs/Web/CSS/color-scheme)

## Why

Users requested dark mode in the feedback survey. Many users work in
low-light environments where bright interfaces cause discomfort. Dark mode
is standard in modern web applications.

## How

- Add theme toggle component to navigation
- Create CSS custom properties for color scheme
- Implement system preference detection
- Store user preference in localStorage
- Update documentation with theme customization guide

Example implementation: [theme-switcher](https://web.dev/prefers-color-scheme/)
```

### Bug Report

```markdown
## What

Authentication token expires before refresh occurs. Users see login prompt
during active sessions. Occurs in [#234](https://github.com/owner/repo/issues/234).

See [JWT best practices](https://tools.ietf.org/html/rfc8725) for reference.

## Why

Token refresh logic waits until expiration before requesting new token.
Network latency causes gap between expiration and refresh completion. This
interrupts user workflows and creates poor experience.

## How

- Update refresh trigger to occur before expiration
- Add buffer time of 60 seconds before token expires
- Implement retry logic for failed refresh attempts
- Log refresh timing for monitoring
- Add unit tests for refresh timing edge cases

Reference: [Auth0 token refresh](https://auth0.com/docs/secure/tokens/refresh-tokens)
```

### Refactoring Task

```markdown
## What

Migrate build system from webpack to Vite. This updates the development
tooling and build configuration. Related to [PR #567](https://github.com/owner/repo/pull/567).

See [Vite guide](https://vitejs.dev/guide/) for migration details.

## Why

Current webpack configuration requires significant maintenance. Vite provides
faster development server and simpler configuration. The team approved
tooling modernization in the Q4 planning discussion.

## How

- Install Vite and remove webpack dependencies
- Create `vite.config.ts` based on current webpack config
- Update package.json scripts for dev and build
- Migrate environment variable handling
- Update CI/CD pipeline build commands
- Document new development workflow

Migration guide: [webpack to Vite](https://vitejs.dev/guide/migration.html)
```
