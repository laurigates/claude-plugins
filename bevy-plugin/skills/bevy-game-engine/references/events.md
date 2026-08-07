# Events

Reference material for [`bevy-game-engine`](../SKILL.md). Load this when
decoupling two systems that must communicate without one querying the other's
components.

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

Register each event type on the app (`app.add_event::<CollisionEvent>()`) — the
`EventWriter`/`EventReader` params panic at startup otherwise.

Events are double-buffered and dropped after two frames, so a reader that runs
before its writer in the schedule reads the event one frame late. When the
latency matters, order the systems explicitly (`.after(detect_collisions)`) —
see the `bevy-ecs-patterns` skill for system ordering and sets.
