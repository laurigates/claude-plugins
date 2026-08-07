# Project Architecture

Reference material for [`bevy-game-engine`](../SKILL.md). Load this when laying
out a growing game — where files go, how to group systems, and what to reach for
when the frame budget slips.

## Project structure

```
my_game/
├── Cargo.toml
├── assets/
│   ├── sprites/
│   ├── fonts/
│   ├── sounds/
│   └── shaders/
└── src/
    ├── main.rs
    ├── lib.rs           # Optional library crate
    ├── plugins/
    │   ├── mod.rs
    │   ├── player.rs
    │   ├── enemy.rs
    │   └── ui.rs
    ├── components/
    │   └── mod.rs
    ├── resources/
    │   └── mod.rs
    ├── systems/
    │   └── mod.rs
    └── events/
        └── mod.rs
```

`assets/` is resolved relative to the working directory at run time, not
compiled in — ship it alongside the binary.

## Performance

- Use `Query` filters (`With<T>`, `Without<T>`) to narrow iteration
- Avoid `Query::iter()` when you need specific entities
- Use `Changed<T>` and `Added<T>` filters for reactive systems
- Profile with `bevy_diagnostic` and Tracy
- Use asset preprocessing for production builds

## Code organization

- Group related components, systems, and events into plugins
- Use marker components for entity classification
- Keep systems focused and single-purpose
- Use resources for global game state
- Prefer events over direct component modification for decoupling

## Common patterns

```rust
// Marker components
#[derive(Component)]
struct Enemy;

#[derive(Component)]
struct Bullet;

// Component bundles for common entity types
#[derive(Bundle)]
struct EnemyBundle {
    enemy: Enemy,
    health: Health,
    sprite: SpriteBundle,
}

// System sets for ordering
#[derive(SystemSet, Debug, Clone, PartialEq, Eq, Hash)]
enum GameSet {
    Input,
    Movement,
    Collision,
    Render,
}
```

For archetype layout, parallel query iteration, change-detection mechanics, and
system-set scheduling in depth, use the `bevy-ecs-patterns` skill.
