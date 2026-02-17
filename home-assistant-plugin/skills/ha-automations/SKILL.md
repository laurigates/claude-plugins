---
model: haiku
created: 2025-02-01
modified: 2026-02-14
reviewed: 2026-02-08
name: ha-automations
description: |
  Home Assistant automation creation and management. Use when creating automation rules,
  working with triggers, conditions, actions, scripts, scenes, or blueprints.
  Covers automation patterns, device triggers, and complex conditional logic.
allowed-tools: Read, Edit, Write, Grep, Glob, TodoWrite
---

# Home Assistant Automations

## When to Use This Skill

| Use this skill when... | Use ha-configuration instead when... |
|------------------------|-------------------------------------|
| Creating automation rules | Editing configuration.yaml |
| Writing triggers/conditions/actions | Setting up integrations |
| Working with scripts and scenes | Managing secrets |
| Using blueprints | Organizing packages |
| Device trigger setup | General YAML configuration |

## Automation Structure

```yaml
automation:
  - id: "unique_automation_id"
    alias: "Descriptive Name"
    description: "What this automation does"
    mode: single  # single, restart, queued, parallel

    trigger:
      - platform: state
        entity_id: binary_sensor.motion
        to: "on"

    condition:
      - condition: time
        after: "08:00:00"
        before: "22:00:00"

    action:
      - service: light.turn_on
        target:
          entity_id: light.living_room
```

## Trigger Types

### State Triggers

```yaml
trigger:
  # Basic state change
  - platform: state
    entity_id: binary_sensor.door
    to: "on"
    from: "off"

  # With duration
  - platform: state
    entity_id: binary_sensor.motion
    to: "off"
    for:
      minutes: 5

  # Attribute change
  - platform: state
    entity_id: climate.thermostat
    attribute: current_temperature
```

### Time Triggers

```yaml
trigger:
  # Specific time
  - platform: time
    at: "07:00:00"

  # Input datetime
  - platform: time
    at: input_datetime.alarm_time

  # Time pattern (every hour)
  - platform: time_pattern
    hours: "*"
    minutes: 0
    seconds: 0

  # Every 15 minutes
  - platform: time_pattern
    minutes: "/15"
```

Other trigger types (numeric state, sun, device, event, webhook, template, zone) are documented in [REFERENCE.md](REFERENCE.md).

## Condition Types

### State Conditions

```yaml
condition:
  # Single entity
  - condition: state
    entity_id: binary_sensor.door
    state: "off"

  # Multiple states allowed
  - condition: state
    entity_id: alarm_control_panel.home
    state:
      - armed_home
      - armed_away

  # Check for duration
  - condition: state
    entity_id: binary_sensor.motion
    state: "off"
    for:
      minutes: 10
```

### Time Conditions

```yaml
condition:
  # Time range
  - condition: time
    after: "08:00:00"
    before: "22:00:00"

  # Weekdays only
  - condition: time
    weekday:
      - mon
      - tue
      - wed
      - thu
      - fri

  # Combined
  - condition: time
    after: "09:00:00"
    before: "17:00:00"
    weekday:
      - mon
      - tue
      - wed
      - thu
      - fri
```

Other condition types (numeric state, sun, template, zone, logical, shorthand) are documented in [REFERENCE.md](REFERENCE.md).

## Action Types

### Service Calls

```yaml
action:
  # Basic service call
  - service: light.turn_on
    target:
      entity_id: light.living_room
    data:
      brightness_pct: 80
      color_temp: 350

  # Multiple targets
  - service: light.turn_off
    target:
      entity_id:
        - light.bedroom
        - light.bathroom
      area_id: upstairs
```

### Delays and Waits

```yaml
action:
  - service: light.turn_on
    target:
      entity_id: light.living_room

  # Fixed delay
  - delay:
      seconds: 30

  # Wait for trigger
  - wait_for_trigger:
      - platform: state
        entity_id: binary_sensor.motion
        to: "off"
    timeout:
      minutes: 5
    continue_on_timeout: true

  # Wait for template
  - wait_template: "{{ is_state('light.bedroom', 'off') }}"
    timeout: "00:05:00"
```

### If/Then/Else (Modern)

```yaml
action:
  - if:
      - condition: state
        entity_id: binary_sensor.motion
        state: "on"
    then:
      - service: light.turn_on
        target:
          entity_id: light.hallway
    else:
      - service: light.turn_off
        target:
          entity_id: light.hallway
```

For advanced action patterns (choose, repeat, variables, parallel execution), scripts, scenes, and common automation patterns, see [REFERENCE.md](REFERENCE.md).

## Automation Modes

| Mode | Behavior |
|------|----------|
| `single` | Ignore new triggers while running |
| `restart` | Stop current run, start new |
| `queued` | Queue up to `max` runs |
| `parallel` | Run up to `max` in parallel |

```yaml
automation:
  - alias: "Motion Light"
    mode: restart
    max: 10  # For queued/parallel
    max_exceeded: silent  # silent, warning, error
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Find automation | `grep -r "alias:" config/automations.yaml` |
| Find triggers | `grep -r "platform: state" config/ --include="*.yaml"` |
| List scripts | `grep -r "^  [a-z_]*:" config/scripts.yaml` |
| Find scenes | `grep -r "^  - name:" config/scenes.yaml` |
| Check automation IDs | `grep -r "^  - id:" config/automations.yaml` |
