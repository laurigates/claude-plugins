# Input Handling

Reference material for [`bevy-game-engine`](../SKILL.md). Load this when
reading player input — keyboard, mouse, or gamepad.

## Keyboard

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
```

`ButtonInput<T>` distinguishes three states: `pressed()` (held this frame),
`just_pressed()` (edge on this frame), and `just_released()`.

## Mouse

```rust
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

Cursor position comes from the `Window` component, not from the input resource,
and is `None` while the cursor is outside the window.

## Gamepad and advanced input

Gamepad buttons and axes follow the same `ButtonInput` / `Axis` resource shape.
For rebindable actions, layered input contexts, and multi-device abstraction,
add `leafwing-input-manager` (see the essential-commands block in
[`SKILL.md`](../SKILL.md)).
