---
name: Bevy Game Engine
description: Bevy game engine development including ECS architecture, rendering, input handling, asset management, and game loop design. Use when building games with Bevy, working with entities/components/systems, or when the user mentions Bevy, game development in Rust, or 2D/3D games.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Bevy Game Engine

Expert knowledge for developing games with Bevy, the data-driven game engine built in Rust with a focus on ergonomics, modularity, and performance.

## Core Expertise

**Bevy Architecture**
- **Entity Component System (ECS)**: Data-oriented design with entities, components, and systems
- **Plugin System**: Modular game organization with reusable plugins
- **Schedules**: System ordering and execution timing
- **Resources**: Global singleton data accessible to systems
- **Events**: Typed message passing between systems
- **States**: Game state management and transitions

**Rendering**
- **2D Rendering**: Sprites, sprite sheets, text rendering, 2D cameras
- **3D Rendering**: PBR materials, meshes, lighting, shadows, cameras
- **UI**: bevy_ui for in-game interfaces
- **Shaders**: Custom WGSL shaders and render pipelines

## Key Capabilities

**ECS Fundamentals**
```rust
use bevy::prelude::*;

// Components are plain data structs
#[derive(Component)]
struct Player;

#[derive(Component)]
struct Health(f32);

#[derive(Component)]
struct Velocity(Vec2);

// Spawn entities with components
fn spawn_player(mut commands: Commands) {
    commands.spawn((
        Player,
        Health(100.0),
        Velocity(Vec2::ZERO),
        SpriteBundle {
            transform: Transform::from_xyz(0.0, 0.0, 0.0),
            ..default()
        },
    ));
}

// Systems query for components
fn move_player(
    time: Res<Time>,
    mut query: Query<(&Velocity, &mut Transform), With<Player>>,
) {
    for (velocity, mut transform) in &mut query {
        transform.translation += velocity.0.extend(0.0) * time.delta_seconds();
    }
}
```

**App Structure**
```rust
use bevy::prelude::*;

fn main() {
    App::new()
        // Default plugins (window, rendering, input, etc.)
        .add_plugins(DefaultPlugins)
        // Custom plugins
        .add_plugins(GamePlugin)
        // Resources
        .insert_resource(GameSettings::default())
        // Startup systems (run once)
        .add_systems(Startup, setup)
        // Update systems (run every frame)
        .add_systems(Update, (
            player_movement,
            collision_detection,
            update_score,
        ))
        .run();
}

// Organize with plugins
pub struct GamePlugin;

impl Plugin for GamePlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_player)
           .add_systems(Update, player_input);
    }
}
```

**Input Handling**
```rust
fn player_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mut query: Query<&mut Velocity, With<Player>>,
) {
    let mut direction = Vec2::ZERO;

    if keyboard.pressed(KeyCode::KeyW) { direction.y += 1.0; }
    if keyboard.pressed(KeyCode::KeyS) { direction.y -= 1.0; }
    if keyboard.pressed(KeyCode::KeyA) { direction.x -= 1.0; }
    if keyboard.pressed(KeyCode::KeyD) { direction.x += 1.0; }

    for mut velocity in &mut query {
        velocity.0 = direction.normalize_or_zero() * 200.0;
    }
}

// Mouse input
fn mouse_click(
    mouse: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
) {
    if mouse.just_pressed(MouseButton::Left) {
        if let Some(position) = windows.single().cursor_position() {
            println!("Clicked at: {:?}", position);
        }
    }
}
```

**Asset Loading**
```rust
#[derive(Resource)]
struct GameAssets {
    player_sprite: Handle<Image>,
    font: Handle<Font>,
    sound: Handle<AudioSource>,
}

fn load_assets(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
) {
    commands.insert_resource(GameAssets {
        player_sprite: asset_server.load("sprites/player.png"),
        font: asset_server.load("fonts/game.ttf"),
        sound: asset_server.load("sounds/jump.ogg"),
    });
}

// Check if assets are loaded
fn check_assets_loaded(
    asset_server: Res<AssetServer>,
    assets: Res<GameAssets>,
    mut next_state: ResMut<NextState<GameState>>,
) {
    use bevy::asset::LoadState;

    if asset_server.get_load_state(&assets.player_sprite) == Some(LoadState::Loaded) {
        next_state.set(GameState::Playing);
    }
}
```

**Game States**
```rust
#[derive(States, Debug, Clone, Eq, PartialEq, Hash, Default)]
enum GameState {
    #[default]
    Loading,
    Menu,
    Playing,
    Paused,
    GameOver,
}

fn setup_states(app: &mut App) {
    app.init_state::<GameState>()
       .add_systems(OnEnter(GameState::Menu), setup_menu)
       .add_systems(OnExit(GameState::Menu), cleanup_menu)
       .add_systems(Update, menu_input.run_if(in_state(GameState::Menu)))
       .add_systems(Update, game_logic.run_if(in_state(GameState::Playing)));
}

fn pause_game(
    keyboard: Res<ButtonInput<KeyCode>>,
    state: Res<State<GameState>>,
    mut next_state: ResMut<NextState<GameState>>,
) {
    if keyboard.just_pressed(KeyCode::Escape) {
        match state.get() {
            GameState::Playing => next_state.set(GameState::Paused),
            GameState::Paused => next_state.set(GameState::Playing),
            _ => {}
        }
    }
}
```

**Events**
```rust
#[derive(Event)]
struct CollisionEvent {
    entity_a: Entity,
    entity_b: Entity,
}

#[derive(Event)]
struct ScoreEvent(u32);

fn detect_collisions(
    mut collision_events: EventWriter<CollisionEvent>,
    query: Query<(Entity, &Transform, &Collider)>,
) {
    // Collision detection logic
    for [(entity_a, transform_a, _), (entity_b, transform_b, _)] in query.iter_combinations() {
        if colliding(transform_a, transform_b) {
            collision_events.send(CollisionEvent { entity_a, entity_b });
        }
    }
}

fn handle_collisions(
    mut collision_events: EventReader<CollisionEvent>,
    mut score_events: EventWriter<ScoreEvent>,
) {
    for event in collision_events.read() {
        // Handle collision
        score_events.send(ScoreEvent(10));
    }
}
```

## Essential Commands

```bash
# Create new Bevy project
cargo new my_game
cd my_game
cargo add bevy

# Run with fast compile times (debug)
cargo run

# Run with optimizations
cargo run --release

# Enable dynamic linking for faster compiles (dev only)
cargo run --features bevy/dynamic_linking

# Common dev dependencies
cargo add bevy_egui           # Debug UI
cargo add bevy_rapier2d       # 2D physics
cargo add bevy_rapier3d       # 3D physics
cargo add bevy_asset_loader   # Asset loading helpers
cargo add leafwing-input-manager  # Advanced input
```

## Project Structure

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

## Best Practices

**Performance**
- Use `Query` filters (`With<T>`, `Without<T>`) to narrow iteration
- Avoid `Query::iter()` when you need specific entities
- Use `Changed<T>` and `Added<T>` filters for reactive systems
- Profile with `bevy_diagnostic` and Tracy
- Use asset preprocessing for production builds

**Code Organization**
- Group related components, systems, and events into plugins
- Use marker components for entity classification
- Keep systems focused and single-purpose
- Use resources for global game state
- Prefer events over direct component modification for decoupling

**Common Patterns**
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

For detailed ECS patterns, advanced queries, and system scheduling, see the bevy-ecs-patterns skill.
