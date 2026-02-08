---
model: haiku
created: 2025-02-01
modified: 2025-02-01
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

### Numeric State Triggers

```yaml
trigger:
  # Above threshold
  - platform: numeric_state
    entity_id: sensor.temperature
    above: 25

  # Below threshold
  - platform: numeric_state
    entity_id: sensor.battery
    below: 20

  # Between range
  - platform: numeric_state
    entity_id: sensor.humidity
    above: 30
    below: 60

  # With duration
  - platform: numeric_state
    entity_id: sensor.power
    above: 1000
    for:
      minutes: 10
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

### Sun Triggers

```yaml
trigger:
  # Sunset
  - platform: sun
    event: sunset
    offset: "-00:30:00"  # 30 min before

  # Sunrise
  - platform: sun
    event: sunrise
    offset: "00:15:00"  # 15 min after

  # Sun elevation
  - platform: numeric_state
    entity_id: sun.sun
    attribute: elevation
    below: -6  # Civil twilight
```

### Device Triggers

```yaml
trigger:
  # Button press
  - platform: device
    domain: mqtt
    device_id: abc123
    type: action
    subtype: single

  # Zigbee button
  - platform: device
    device_id: def456
    domain: zha
    type: remote_button_short_press
    subtype: button_1
```

### Event Triggers

```yaml
trigger:
  # HA start
  - platform: homeassistant
    event: start

  # Custom event
  - platform: event
    event_type: custom_event
    event_data:
      action: button_press

  # Tag scanned
  - platform: tag
    tag_id: my-tag-id
```

### Webhook Triggers

```yaml
trigger:
  - platform: webhook
    webhook_id: my_webhook_id
    allowed_methods:
      - POST
    local_only: false
```

### Template Triggers

```yaml
trigger:
  - platform: template
    value_template: >-
      {{ states('sensor.temp') | float > 25 and
         is_state('binary_sensor.window', 'off') }}
    for:
      minutes: 5
```

### Zone Triggers

```yaml
trigger:
  - platform: zone
    entity_id: person.user
    zone: zone.home
    event: enter  # or leave

  # Multiple people
  - platform: zone
    entity_id:
      - person.user1
      - person.user2
    zone: zone.work
    event: leave
```

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

### Numeric State Conditions

```yaml
condition:
  - condition: numeric_state
    entity_id: sensor.temperature
    above: 18
    below: 25
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

### Sun Conditions

```yaml
condition:
  - condition: sun
    after: sunset
    after_offset: "-01:00:00"
    before: sunrise
    before_offset: "00:30:00"
```

### Template Conditions

```yaml
condition:
  - condition: template
    value_template: >-
      {{ states('sensor.power') | float < 100 and
         now().hour >= 6 and now().hour < 23 }}
```

### Zone Conditions

```yaml
condition:
  - condition: zone
    entity_id: person.user
    zone: zone.home
```

### Logical Conditions

```yaml
condition:
  # AND (default)
  - condition: and
    conditions:
      - condition: state
        entity_id: binary_sensor.motion
        state: "on"
      - condition: numeric_state
        entity_id: sensor.lux
        below: 50

  # OR
  - condition: or
    conditions:
      - condition: state
        entity_id: person.user1
        state: home
      - condition: state
        entity_id: person.user2
        state: home

  # NOT
  - condition: not
    conditions:
      - condition: state
        entity_id: input_boolean.guest_mode
        state: "on"
```

### Shorthand Conditions

```yaml
condition:
  # Simple state check (shorthand)
  - "{{ is_state('binary_sensor.door', 'off') }}"

  # Multiple checks
  - "{{ is_state('alarm_control_panel.home', 'armed_away') }}"
  - "{{ states('sensor.battery') | int > 20 }}"
```

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

  # Using device_id
  - service: light.toggle
    target:
      device_id: abc123
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

  # Template delay
  - delay: "{{ states('input_number.delay') | int }}"

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

### Choose (If/Else)

```yaml
action:
  - choose:
      # First condition
      - conditions:
          - condition: state
            entity_id: input_select.mode
            state: "Movie"
        sequence:
          - service: light.turn_on
            target:
              entity_id: light.living_room
            data:
              brightness_pct: 20

      # Second condition
      - conditions:
          - condition: state
            entity_id: input_select.mode
            state: "Party"
        sequence:
          - service: light.turn_on
            target:
              entity_id: light.living_room
            data:
              rgb_color: [255, 0, 0]

    # Default (else)
    default:
      - service: light.turn_on
        target:
          entity_id: light.living_room
        data:
          brightness_pct: 100
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

### Repeat

```yaml
action:
  # Count-based
  - repeat:
      count: 3
      sequence:
        - service: light.toggle
          target:
            entity_id: light.notification
        - delay:
            milliseconds: 500

  # While loop
  - repeat:
      while:
        - condition: state
          entity_id: binary_sensor.motion
          state: "on"
      sequence:
        - service: light.turn_on
          target:
            entity_id: light.hallway
        - delay:
            seconds: 30

  # For each
  - repeat:
      for_each:
        - light.living_room
        - light.bedroom
        - light.kitchen
      sequence:
        - service: light.turn_off
          target:
            entity_id: "{{ repeat.item }}"
        - delay:
            seconds: 1
```

### Variables

```yaml
action:
  - variables:
      current_brightness: "{{ state_attr('light.living_room', 'brightness') | int }}"
      new_brightness: "{{ [current_brightness + 25, 255] | min }}"

  - service: light.turn_on
    target:
      entity_id: light.living_room
    data:
      brightness: "{{ new_brightness }}"
```

### Parallel Execution

```yaml
action:
  - parallel:
      - service: light.turn_on
        target:
          entity_id: light.living_room
      - service: media_player.play_media
        target:
          entity_id: media_player.speaker
        data:
          media_content_id: "http://example.com/sound.mp3"
          media_content_type: music
      - service: notify.mobile_app
        data:
          message: "Welcome home!"
```

## Scripts

```yaml
script:
  morning_routine:
    alias: "Morning Routine"
    icon: mdi:weather-sunny
    mode: single
    fields:
      brightness:
        description: "Light brightness level"
        example: 80
        selector:
          number:
            min: 0
            max: 100
    sequence:
      - service: light.turn_on
        target:
          area_id: bedroom
        data:
          brightness_pct: "{{ brightness | default(50) }}"
          transition: 30
      - delay:
          minutes: 5
      - service: media_player.play_media
        target:
          entity_id: media_player.bedroom_speaker
        data:
          media_content_id: "news"
          media_content_type: music

  flash_lights:
    alias: "Flash Lights"
    mode: restart
    sequence:
      - repeat:
          count: 5
          sequence:
            - service: light.toggle
              target:
                entity_id: "{{ target_light }}"
            - delay:
                milliseconds: 300
```

## Scenes

```yaml
scene:
  - name: "Movie Night"
    icon: mdi:movie
    entities:
      light.living_room:
        state: on
        brightness: 50
        color_temp: 400
      light.ceiling:
        state: off
      media_player.tv:
        state: on
      cover.blinds:
        state: closed

  - name: "Good Morning"
    entities:
      light.bedroom:
        state: on
        brightness: 200
        color_temp: 300
      cover.bedroom_blinds:
        state: open
```

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

## Common Patterns

### Motion-Activated Light

```yaml
automation:
  - alias: "Motion Light"
    mode: restart
    trigger:
      - platform: state
        entity_id: binary_sensor.motion
        to: "on"
    condition:
      - condition: numeric_state
        entity_id: sensor.lux
        below: 50
    action:
      - service: light.turn_on
        target:
          entity_id: light.hallway
      - wait_for_trigger:
          - platform: state
            entity_id: binary_sensor.motion
            to: "off"
            for:
              minutes: 2
      - service: light.turn_off
        target:
          entity_id: light.hallway
```

### Presence-Based Thermostat

```yaml
automation:
  - alias: "Away Mode Thermostat"
    trigger:
      - platform: state
        entity_id: binary_sensor.anyone_home
        to: "off"
        for:
          minutes: 30
    action:
      - service: climate.set_preset_mode
        target:
          entity_id: climate.thermostat
        data:
          preset_mode: away

  - alias: "Home Mode Thermostat"
    trigger:
      - platform: state
        entity_id: binary_sensor.anyone_home
        to: "on"
    action:
      - service: climate.set_preset_mode
        target:
          entity_id: climate.thermostat
        data:
          preset_mode: home
```

### Notification with Actionable Response

```yaml
automation:
  - alias: "Door Left Open"
    trigger:
      - platform: state
        entity_id: binary_sensor.front_door
        to: "on"
        for:
          minutes: 5
    action:
      - service: notify.mobile_app_phone
        data:
          title: "Door Alert"
          message: "Front door has been open for 5 minutes"
          data:
            actions:
              - action: "DISMISS"
                title: "Dismiss"
              - action: "LOCK_DOOR"
                title: "Lock Door"

  - alias: "Handle Door Notification Response"
    trigger:
      - platform: event
        event_type: mobile_app_notification_action
        event_data:
          action: "LOCK_DOOR"
    action:
      - service: lock.lock
        target:
          entity_id: lock.front_door
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Find automation | `grep -r "alias:" config/automations.yaml` |
| Find triggers | `grep -r "platform: state" config/ --include="*.yaml"` |
| List scripts | `grep -r "^  [a-z_]*:" config/scripts.yaml` |
| Find scenes | `grep -r "^  - name:" config/scenes.yaml` |
| Check automation IDs | `grep -r "^  - id:" config/automations.yaml` |
