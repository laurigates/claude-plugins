---
model: haiku
created: 2025-02-01
modified: 2025-02-01
reviewed: 2025-02-01
name: ha-entities
description: |
  Home Assistant entity and domain management. Use when working with entity IDs,
  device classes, customizations, template entities, groups, or understanding
  entity naming conventions and domain-specific attributes.
allowed-tools: Read, Edit, Write, Grep, Glob, TodoWrite
---

# Home Assistant Entities

## When to Use This Skill

| Use this skill when... | Use ha-automations instead when... |
|------------------------|-----------------------------------|
| Understanding entity domains | Creating automation rules |
| Customizing entities | Working with triggers/actions |
| Creating template sensors | Writing automation conditions |
| Setting up groups | Working with scripts/scenes |
| Working with device classes | Handling events |

## Entity ID Structure

```
domain.object_id
```

**Examples:**
- `light.living_room_ceiling`
- `sensor.outdoor_temperature`
- `binary_sensor.front_door_contact`
- `switch.garden_irrigation`

## Common Domains

| Domain | Description | Example |
|--------|-------------|---------|
| `light` | Lighting control | `light.kitchen` |
| `switch` | On/off switches | `switch.outlet` |
| `sensor` | Numeric sensors | `sensor.temperature` |
| `binary_sensor` | On/off sensors | `binary_sensor.motion` |
| `climate` | HVAC control | `climate.thermostat` |
| `cover` | Blinds, garage doors | `cover.garage` |
| `lock` | Door locks | `lock.front_door` |
| `media_player` | Media devices | `media_player.tv` |
| `camera` | Camera feeds | `camera.front_yard` |
| `vacuum` | Robot vacuums | `vacuum.roomba` |
| `fan` | Fan control | `fan.bedroom` |
| `alarm_control_panel` | Alarm systems | `alarm_control_panel.home` |
| `person` | People tracking | `person.john` |
| `device_tracker` | Device location | `device_tracker.phone` |
| `weather` | Weather info | `weather.home` |
| `input_boolean` | Virtual toggle | `input_boolean.guest_mode` |
| `input_number` | Virtual number | `input_number.target_temp` |
| `input_select` | Virtual dropdown | `input_select.house_mode` |
| `input_text` | Virtual text | `input_text.message` |
| `input_datetime` | Virtual date/time | `input_datetime.alarm` |
| `input_button` | Virtual button | `input_button.reset` |
| `automation` | Automations | `automation.motion_light` |
| `script` | Scripts | `script.morning_routine` |
| `scene` | Scenes | `scene.movie_night` |
| `group` | Entity groups | `group.all_lights` |
| `timer` | Countdown timers | `timer.laundry` |
| `counter` | Counters | `counter.guests` |
| `zone` | Geographic zones | `zone.home` |
| `sun` | Sun position | `sun.sun` |

For complete device class tables (binary sensor and sensor), see [REFERENCE.md](REFERENCE.md).

## Entity Customization

### customize.yaml

```yaml
# Single entity
light.living_room:
  friendly_name: "Living Room Light"
  icon: mdi:ceiling-light

# Binary sensor
binary_sensor.front_door:
  friendly_name: "Front Door"
  device_class: door

# Sensor
sensor.outdoor_temperature:
  friendly_name: "Outdoor Temperature"
  device_class: temperature
  unit_of_measurement: "°C"
```

### Glob Customization

```yaml
customize_glob:
  "light.*_ceiling":
    icon: mdi:ceiling-light

  "sensor.*_temperature":
    device_class: temperature
    unit_of_measurement: "°C"

  "binary_sensor.*_motion":
    device_class: motion
```

## Template Sensors

```yaml
template:
  - sensor:
      # Simple state
      - name: "Average Temperature"
        unit_of_measurement: "°C"
        device_class: temperature
        state: >-
          {{ ((states('sensor.living_room_temp') | float +
               states('sensor.bedroom_temp') | float +
               states('sensor.kitchen_temp') | float) / 3) | round(1) }}

      # With attributes
      - name: "Power Usage"
        unit_of_measurement: "W"
        device_class: power
        state: "{{ states('sensor.energy_meter_power') }}"
        attributes:
          cost_per_hour: >-
            {{ (states('sensor.energy_meter_power') | float * 0.15 / 1000) | round(2) }}

      # Availability
      - name: "Solar Power"
        unit_of_measurement: "W"
        device_class: power
        state: "{{ states('sensor.inverter_power') }}"
        availability: "{{ states('sensor.inverter_power') != 'unavailable' }}"
```

For template binary sensors, switches, buttons, numbers, groups, utility meters, counters, and timers, see [REFERENCE.md](REFERENCE.md).

## State Attributes

### Common Attributes

| Domain | Common Attributes |
|--------|-------------------|
| `light` | `brightness`, `color_temp`, `rgb_color`, `hs_color`, `effect` |
| `climate` | `temperature`, `current_temperature`, `hvac_action`, `preset_mode` |
| `media_player` | `volume_level`, `media_title`, `media_artist`, `source` |
| `cover` | `current_position`, `current_tilt_position` |
| `weather` | `temperature`, `humidity`, `pressure`, `wind_speed`, `forecast` |
| `person` | `source`, `latitude`, `longitude`, `gps_accuracy` |
| `sun` | `elevation`, `azimuth`, `next_rising`, `next_setting` |

### Accessing Attributes

```yaml
# In templates
{{ state_attr('light.living_room', 'brightness') }}
{{ state_attr('climate.thermostat', 'current_temperature') }}
{{ state_attr('sun.sun', 'elevation') }}

# In conditions
condition:
  - condition: numeric_state
    entity_id: light.living_room
    attribute: brightness
    above: 100
```

## Quick Reference

### State Functions

| Function | Description | Example |
|----------|-------------|---------|
| `states('entity')` | Get state | `states('sensor.temp')` |
| `state_attr('entity', 'attr')` | Get attribute | `state_attr('light.x', 'brightness')` |
| `is_state('entity', 'value')` | Check state | `is_state('light.x', 'on')` |
| `is_state_attr('entity', 'attr', 'val')` | Check attribute | `is_state_attr('climate.x', 'hvac_action', 'heating')` |
| `states.domain` | All entities in domain | `states.light` |
| `expand('group.x')` | Expand group members | `expand('group.all_lights')` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Find entity usage | `grep -r "entity_id:" config/ --include="*.yaml"` |
| List customizations | `grep -rA2 "^[a-z_]*\\..*:" config/customize.yaml` |
| Find template sensors | `grep -rB2 "platform: template" config/ --include="*.yaml"` |
| Find groups | `grep -rA5 "^group:" config/ --include="*.yaml"` |
| List domains used | `grep -roh "[a-z_]*\\." config/ --include="*.yaml" \| sort -u` |
