# migration-patterns-plugin

Safe database and system migration patterns for zero-downtime transitions.

## Skills

| Skill | Model | Description |
|-------|-------|-------------|
| dual-write | opus | Dual write (double write) pattern for keeping two data stores in sync during migration |
| shadow-mode | opus | Shadow mode (dark launching) pattern for validating new systems under production traffic |

## Patterns Covered

### Dual Write

During a database migration, the application writes to both the old and new system simultaneously. Reads can be compared between them to validate consistency before cutting over.

**Use when:** Migrating databases, switching storage backends, zero-downtime schema changes.

### Shadow Mode

Production requests are mirrored to a shadow deployment in the background. The shadow's responses are discarded (only the production response reaches the user), but responses are logged and compared to verify the new system behaves correctly under real traffic.

**Use when:** Validating replacement services, testing under production load, comparing response correctness.

### Combined Usage

These patterns are complementary tactics within the Strangler Fig migration strategy:
- Shadow mode validates read behavior
- Dual write keeps both systems in sync
- Together they enable safe, gradual migration with rollback at every phase

## Installation

Add to your Claude Code plugin registry or install from the marketplace.
