---
name: Bevy ECS Patterns
description: Advanced Bevy ECS patterns including complex queries, system scheduling, change detection, entity relationships, and performance optimization. Use when working on advanced Bevy game architecture, optimizing ECS performance, or implementing complex game systems.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Bevy ECS Patterns

Advanced patterns and techniques for Bevy's Entity Component System, focusing on performance, maintainability, and complex game architectures.

## Core Expertise

**Advanced Queries**
- Complex query filters and combinations
- Query state and caching
- Entity relationships and hierarchies
- Parallel iteration strategies

**System Scheduling**
- System ordering and dependencies
- Run conditions and gating
- System sets and scheduling
- Fixed timestep systems

**Change Detection**
- `Changed<T>` and `Added<T>` filters
- `Ref<T>` for change tracking
- Efficient reactive systems

## Advanced Query Patterns

**Query Filters**
```rust
use bevy::prelude::*;

// Multiple filters
fn targeting_system(
    query: Query<
        (&Transform, &mut Target),
        (With<Enemy>, Without<Dead>, Changed<Health>)
    >,
) {
    for (transform, mut target) in &query {
        // Only enemies that are alive and recently damaged
    }
}

// Optional components
fn flexible_system(
    query: Query<(&Transform, Option<&Velocity>, Option<&Acceleration>)>,
) {
    for (transform, velocity, acceleration) in &query {
        if let Some(vel) = velocity {
            // Has velocity
        }
    }
}

// Or filters
fn pickup_system(
    query: Query<Entity, Or<(With<HealthPickup>, With<AmmoPickup>)>>,
) {
    for entity in &query {
        // Process any pickup type
    }
}
```

**Multiple Queries with Conflicts**
```rust
// Use ParamSet when queries have conflicting access
fn combat_system(
    mut param_set: ParamSet<(
        Query<&mut Health, With<Player>>,
        Query<&mut Health, With<Enemy>>,
    )>,
) {
    // Access one query at a time
    for mut health in param_set.p0().iter_mut() {
        health.0 += 1.0; // Heal player
    }

    for mut health in param_set.p1().iter_mut() {
        health.0 -= 10.0; // Damage enemies
    }
}

// Query transmutation for flexible access
fn dynamic_query(
    all_entities: Query<(Entity, &Transform)>,
    players: Query<&Player>,
) {
    for (entity, transform) in &all_entities {
        if players.get(entity).is_ok() {
            // This is a player
        }
    }
}
```

**Entity Relationships**
```rust
// Parent-child hierarchies
#[derive(Component)]
struct Inventory;

#[derive(Component)]
struct InventorySlot(usize);

fn spawn_inventory(mut commands: Commands) {
    commands.spawn((Inventory, SpatialBundle::default()))
        .with_children(|parent| {
            for i in 0..10 {
                parent.spawn((InventorySlot(i), SpriteBundle::default()));
            }
        });
}

// Query parent from child
fn child_system(
    children: Query<(&InventorySlot, &Parent)>,
    parents: Query<&Inventory>,
) {
    for (slot, parent) in &children {
        if let Ok(inventory) = parents.get(parent.get()) {
            // Access parent inventory
        }
    }
}

// Query children from parent
fn parent_system(
    parents: Query<&Children, With<Inventory>>,
    slots: Query<&InventorySlot>,
) {
    for children in &parents {
        for &child in children.iter() {
            if let Ok(slot) = slots.get(child) {
                // Access child slot
            }
        }
    }
}
```

## System Scheduling

**System Ordering**
```rust
fn configure_systems(app: &mut App) {
    app.add_systems(Update, (
        // Sequential execution
        read_input,
        apply_movement.after(read_input),
        check_collisions.after(apply_movement),
        update_ui.after(check_collisions),
    ));

    // Alternative: chain for strict ordering
    app.add_systems(Update, (
        read_input,
        apply_movement,
        check_collisions,
        update_ui,
    ).chain());

    // Parallel by default when no dependencies
    app.add_systems(Update, (
        update_animations,  // Runs in parallel
        update_particles,   // with these systems
        update_audio,
    ));
}
```

**System Sets**
```rust
#[derive(SystemSet, Debug, Clone, PartialEq, Eq, Hash)]
enum PhysicsSet {
    Movement,
    CollisionDetection,
    CollisionResolution,
}

fn configure_physics(app: &mut App) {
    app.configure_sets(Update, (
        PhysicsSet::Movement,
        PhysicsSet::CollisionDetection.after(PhysicsSet::Movement),
        PhysicsSet::CollisionResolution.after(PhysicsSet::CollisionDetection),
    ));

    app.add_systems(Update, (
        apply_velocity.in_set(PhysicsSet::Movement),
        apply_gravity.in_set(PhysicsSet::Movement),
        broad_phase.in_set(PhysicsSet::CollisionDetection),
        narrow_phase.in_set(PhysicsSet::CollisionDetection),
        resolve_collisions.in_set(PhysicsSet::CollisionResolution),
    ));
}
```

**Run Conditions**
```rust
fn configure_conditional_systems(app: &mut App) {
    app.add_systems(Update, (
        // State-based conditions
        game_logic.run_if(in_state(GameState::Playing)),

        // Resource-based conditions
        debug_ui.run_if(resource_exists::<DebugMode>),

        // Custom conditions
        spawn_enemies.run_if(should_spawn_enemy),

        // Combined conditions
        player_input.run_if(
            in_state(GameState::Playing)
                .and_then(not(resource_exists::<Paused>))
        ),
    ));
}

fn should_spawn_enemy(
    time: Res<Time>,
    enemy_count: Query<&Enemy>,
) -> bool {
    enemy_count.iter().count() < 10 && time.elapsed_seconds() > 5.0
}
```

**Fixed Timestep**
```rust
fn configure_fixed_timestep(app: &mut App) {
    app.insert_resource(Time::<Fixed>::from_seconds(1.0 / 60.0));

    app.add_systems(FixedUpdate, (
        physics_step,
        apply_forces,
        integrate_positions,
    ));
}

fn physics_step(
    time: Res<Time<Fixed>>,
    mut query: Query<(&mut Transform, &Velocity)>,
) {
    let dt = time.delta_seconds();
    for (mut transform, velocity) in &mut query {
        transform.translation += velocity.0.extend(0.0) * dt;
    }
}
```

## Change Detection

**Reactive Systems**
```rust
// React to component changes
fn on_health_change(
    query: Query<(Entity, &Health), Changed<Health>>,
    mut death_events: EventWriter<DeathEvent>,
) {
    for (entity, health) in &query {
        if health.0 <= 0.0 {
            death_events.send(DeathEvent(entity));
        }
    }
}

// React to component additions
fn on_enemy_spawn(
    query: Query<Entity, Added<Enemy>>,
    mut enemy_count: ResMut<EnemyCount>,
) {
    for entity in &query {
        enemy_count.0 += 1;
        println!("Enemy spawned: {:?}", entity);
    }
}

// Track if component was changed
fn track_changes(
    query: Query<Ref<Transform>, With<Player>>,
) {
    for transform in &query {
        if transform.is_changed() {
            println!("Player moved to: {:?}", transform.translation);
        }
        if transform.is_added() {
            println!("Player spawned!");
        }
    }
}
```

**Deferred Operations**
```rust
// Commands are deferred until the end of the stage
fn spawn_system(mut commands: Commands) {
    let entity = commands.spawn(Enemy).id();
    // Entity exists but components aren't queryable yet
}

// For immediate access, use World directly (exclusive systems)
fn exclusive_spawn(world: &mut World) {
    let entity = world.spawn(Enemy).id();
    // Components are immediately accessible
    world.entity_mut(entity).insert(Health(100.0));
}
```

## Performance Patterns

**Parallel Iteration**
```rust
use bevy::prelude::*;

fn parallel_update(
    mut query: Query<(&mut Transform, &Velocity)>,
) {
    // Automatically parallelized when possible
    query.par_iter_mut().for_each(|(mut transform, velocity)| {
        transform.translation += velocity.0.extend(0.0);
    });
}
```

**Query Caching**
```rust
#[derive(Resource)]
struct CachedEnemies {
    entities: Vec<Entity>,
    last_update: f32,
}

fn cache_enemies(
    time: Res<Time>,
    query: Query<Entity, With<Enemy>>,
    mut cache: ResMut<CachedEnemies>,
) {
    // Update cache periodically instead of every frame
    if time.elapsed_seconds() - cache.last_update > 0.1 {
        cache.entities = query.iter().collect();
        cache.last_update = time.elapsed_seconds();
    }
}
```

**Component Storage Hints**
```rust
// SparseSet for frequently added/removed components
#[derive(Component)]
#[component(storage = "SparseSet")]
struct Burning;

// Table storage (default) for stable components
#[derive(Component)]
struct Health(f32);

// Use marker components efficiently
#[derive(Component)]
struct Player;  // Zero-sized type (ZST)
```

**Batch Operations**
```rust
fn batch_spawn(mut commands: Commands) {
    // More efficient than individual spawns
    commands.spawn_batch((0..1000).map(|i| (
        Enemy,
        Health(100.0),
        Transform::from_xyz(i as f32 * 10.0, 0.0, 0.0),
    )));
}
```

## Entity Commands Pattern

```rust
// Extend Commands with custom operations
trait SpawnEnemyExt {
    fn spawn_enemy(&mut self, position: Vec3, health: f32) -> Entity;
}

impl SpawnEnemyExt for Commands<'_, '_> {
    fn spawn_enemy(&mut self, position: Vec3, health: f32) -> Entity {
        self.spawn((
            Enemy,
            Health(health),
            Transform::from_translation(position),
            SpriteBundle::default(),
        )).id()
    }
}

// Usage
fn spawn_wave(mut commands: Commands) {
    for i in 0..10 {
        commands.spawn_enemy(Vec3::new(i as f32 * 50.0, 0.0, 0.0), 100.0);
    }
}
```

## Best Practices

**Query Design**
- Use the most specific query possible
- Prefer `Changed<T>` over checking every entity
- Use `Option<&T>` sparingly; prefer separate queries
- Profile query iteration with `bevy_diagnostic`

**System Design**
- Keep systems small and focused
- Use events for cross-system communication
- Avoid storing `Entity` IDs in components when possible
- Use run conditions to skip unnecessary work

**Memory Layout**
- Group related components that are accessed together
- Use SparseSet storage for temporary components
- Consider archetype fragmentation with many component combinations

**Debugging**
```rust
// Enable bevy diagnostics
app.add_plugins(bevy::diagnostic::DiagnosticsPlugin)
   .add_plugins(bevy::diagnostic::FrameTimeDiagnosticsPlugin)
   .add_plugins(bevy::diagnostic::EntityCountDiagnosticsPlugin);

// Log system execution
app.add_plugins(bevy::diagnostic::SystemInformationDiagnosticsPlugin);
```
