# codebase-attributes-plugin

Structured codebase health attributes with severity-based agent routing.

## Skills

| Skill | Description |
|-------|-------------|
| `/attributes:collect` | Collect codebase health attributes as structured JSON |
| `/attributes:route` | Route to specialized agents based on attribute severity |
| `/attributes:dashboard` | Compact text-based health dashboard with findings |

## How It Works

1. **Collect** — `/attributes:collect` scans the codebase for health signals (README, tests, linter, CI, security) and emits structured JSON with severity and remediation actions
2. **Route** — `/attributes:route` reads the attributes and delegates to the right agents (security-audit, test, docs, etc.) based on priority
3. **Dashboard** — `/attributes:dashboard` renders a compact terminal-style health overview

## Attribute Schema

Each attribute contains:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Kebab-case identifier (e.g., `missing-readme`) |
| `category` | string | `docs`, `tests`, `security`, `quality`, `ci` |
| `severity` | string | `critical`, `high`, `medium`, `low`, `info` |
| `description` | string | Human-readable finding |
| `source` | string | Collector that produced this attribute |
| `actions` | array | Remediation actions with agent targets |

## Integration

Works with the `git-repo-agent` Python tool (which produces the same JSON schema) and the `agents-plugin` router agents.
