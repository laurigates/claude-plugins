# Bevy Plugin

Comprehensive Bevy game engine development support including ECS architecture, rendering, input handling, asset management, and advanced game architecture patterns.

## Overview

This plugin provides expert guidance for developing games with Bevy, the data-driven game engine built in Rust. It covers both fundamental Bevy concepts and advanced ECS patterns for building performant, maintainable games.

## Skills

### bevy-game-engine

Core Bevy development expertise including:

- **ECS Architecture**: Entity-Component-System fundamentals, entities, components, systems
- **Plugin System**: Modular game organization with reusable plugins
- **Rendering**: 2D/3D rendering, sprites, meshes, materials, lighting, cameras, shaders
- **Input Handling**: Keyboard, mouse, gamepad input processing
- **Asset Management**: Loading and managing sprites, fonts, sounds, textures
- **Game States**: State management, transitions, and conditional systems
- **Events**: Typed message passing between systems
- **Resources**: Global singleton data accessible to systems

**Use when**: Building games with Bevy, working with entities/components/systems, implementing game features, or when the user mentions Bevy, game development in Rust, or 2D/3D games.

### bevy-ecs-patterns

Advanced ECS patterns and techniques:

- **Advanced Queries**: Complex filters, combinations, query state, entity relationships
- **System Scheduling**: Ordering, dependencies, run conditions, system sets
- **Change Detection**: Reactive systems with `Changed<T>`, `Added<T>`, and `Ref<T>`
- **Performance Optimization**: Parallel iteration, query caching, component storage hints
- **Entity Hierarchies**: Parent-child relationships, query patterns
- **Fixed Timestep**: Physics and deterministic game logic
- **Batch Operations**: Efficient entity spawning and updates

**Use when**: Working on advanced Bevy game architecture, optimizing ECS performance, implementing complex game systems, or debugging performance issues.

## When to Use This Plugin

Enable this plugin when:

- Developing games with Bevy
- Working with Entity-Component-System architecture
- Implementing game features (movement, collision, AI, etc.)
- Optimizing game performance
- Designing game architecture and systems
- Integrating Bevy plugins and third-party crates
- Working with 2D or 3D rendering in Bevy
- Building game prototypes or production games in Rust

## Key Features

- **Data-Driven Design**: Leverage Bevy's ECS for clean separation of data and logic
- **Performance Focused**: Best practices for high-performance game loops
- **Modular Architecture**: Plugin-based organization for reusable game systems
- **Type Safety**: Rust's type system for catching bugs at compile time
- **Modern Rendering**: PBR, custom shaders, 2D/3D rendering pipelines
- **Ergonomic API**: Bevy's builder patterns and query system

## Common Patterns

### Basic Game Structure

```rust
use bevy::prelude::*;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins(GamePlugin)
        .run();
}

struct GamePlugin;

impl Plugin for GamePlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, setup)
           .add_systems(Update, (player_movement, enemy_ai));
    }
}
```

### ECS Query Pattern

```rust
fn movement_system(
    time: Res<Time>,
    mut query: Query<(&Velocity, &mut Transform), With<Player>>,
) {
    for (velocity, mut transform) in &mut query {
        transform.translation += velocity.0.extend(0.0) * time.delta_seconds();
    }
}
```

### Event-Driven Communication

```rust
#[derive(Event)]
struct CollisionEvent(Entity, Entity);

fn detect_collisions(mut events: EventWriter<CollisionEvent>) {
    // Detection logic
    events.send(CollisionEvent(entity_a, entity_b));
}

fn handle_collisions(mut events: EventReader<CollisionEvent>) {
    for event in events.read() {
        // Handle collision
    }
}
```

## Related Skills

- **rust-plugin**: General Rust development patterns and best practices
- **testing-plugin**: Testing strategies for Bevy games

## Resources

- [Bevy Documentation](https://bevyengine.org/learn/)
- [Bevy Assets](https://bevyengine.org/assets/)
- [Bevy Examples](https://github.com/bevyengine/bevy/tree/main/examples)
- [Unofficial Bevy Cheat Book](https://bevy-cheatbook.github.io/)
