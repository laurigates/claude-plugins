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

## Device Classes

### Binary Sensor Device Classes

| Class | On State | Off State |
|-------|----------|-----------|
| `battery` | Low | Normal |
| `battery_charging` | Charging | Not charging |
| `cold` | Cold | Normal |
| `connectivity` | Connected | Disconnected |
| `door` | Open | Closed |
| `garage_door` | Open | Closed |
| `gas` | Gas detected | Clear |
| `heat` | Hot | Normal |
| `light` | Light detected | No light |
| `lock` | Unlocked | Locked |
| `moisture` | Wet | Dry |
| `motion` | Motion detected | Clear |
| `occupancy` | Occupied | Clear |
| `opening` | Open | Closed |
| `plug` | Plugged in | Unplugged |
| `power` | Power detected | No power |
| `presence` | Home | Away |
| `problem` | Problem | OK |
| `running` | Running | Not running |
| `safety` | Unsafe | Safe |
| `smoke` | Smoke detected | Clear |
| `sound` | Sound detected | Clear |
| `tamper` | Tampering | Clear |
| `update` | Update available | Up-to-date |
| `vibration` | Vibration | Clear |
| `window` | Open | Closed |

### Sensor Device Classes

| Class | Unit | Description |
|-------|------|-------------|
| `apparent_power` | VA | Apparent power |
| `aqi` | - | Air quality index |
| `atmospheric_pressure` | hPa | Atmospheric pressure |
| `battery` | % | Battery level |
| `carbon_dioxide` | ppm | CO2 concentration |
| `carbon_monoxide` | ppm | CO concentration |
| `current` | A | Electric current |
| `data_rate` | Mbps | Data transfer rate |
| `data_size` | GB | Data size |
| `distance` | m | Distance |
| `duration` | s | Time duration |
| `energy` | kWh | Energy consumption |
| `frequency` | Hz | Frequency |
| `gas` | m³ | Gas consumption |
| `humidity` | % | Relative humidity |
| `illuminance` | lx | Light level |
| `irradiance` | W/m² | Solar irradiance |
| `moisture` | % | Moisture level |
| `monetary` | € | Monetary value |
| `nitrogen_dioxide` | µg/m³ | NO2 concentration |
| `nitrogen_monoxide` | µg/m³ | NO concentration |
| `ozone` | µg/m³ | O3 concentration |
| `ph` | - | pH level |
| `pm1` | µg/m³ | PM1 concentration |
| `pm10` | µg/m³ | PM10 concentration |
| `pm25` | µg/m³ | PM2.5 concentration |
| `power` | W | Power consumption |
| `power_factor` | % | Power factor |
| `precipitation` | mm | Precipitation |
| `precipitation_intensity` | mm/h | Precipitation rate |
| `pressure` | hPa | Pressure |
| `reactive_power` | var | Reactive power |
| `signal_strength` | dBm | Signal strength |
| `sound_pressure` | dB | Sound level |
| `speed` | m/s | Speed |
| `sulphur_dioxide` | µg/m³ | SO2 concentration |
| `temperature` | °C | Temperature |
| `timestamp` | - | Timestamp |
| `volatile_organic_compounds` | µg/m³ | VOC concentration |
| `voltage` | V | Voltage |
| `volume` | L | Volume |
| `water` | L | Water consumption |
| `weight` | kg | Weight |
| `wind_speed` | m/s | Wind speed |

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

# Hide entity from UI
sensor.internal_counter:
  hidden: true
```

### Glob Customization

```yaml
# Customize all entities matching pattern
customize_glob:
  "light.*_ceiling":
    icon: mdi:ceiling-light

  "sensor.*_temperature":
    device_class: temperature
    unit_of_measurement: "°C"

  "binary_sensor.*_motion":
    device_class: motion

  "switch.outlet_*":
    icon: mdi:power-socket-eu
```

## Template Entities

### Template Sensors

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
          daily_estimate: >-
            {{ (states('sensor.energy_meter_power') | float * 24 / 1000) | round(1) }}

      # Availability
      - name: "Solar Power"
        unit_of_measurement: "W"
        device_class: power
        state: "{{ states('sensor.inverter_power') }}"
        availability: "{{ states('sensor.inverter_power') != 'unavailable' }}"
```

### Template Binary Sensors

```yaml
template:
  - binary_sensor:
      - name: "Anyone Home"
        device_class: presence
        state: >-
          {{ is_state('person.user1', 'home') or
             is_state('person.user2', 'home') }}

      - name: "House Secure"
        device_class: safety
        state: >-
          {{ is_state('lock.front_door', 'locked') and
             is_state('lock.back_door', 'locked') and
             is_state('cover.garage', 'closed') }}
        icon: >-
          {% if is_state('binary_sensor.house_secure', 'on') %}
            mdi:shield-check
          {% else %}
            mdi:shield-alert
          {% endif %}

      - name: "Washing Machine Running"
        device_class: running
        state: "{{ states('sensor.washer_power') | float > 10 }}"
        delay_off:
          minutes: 5
```

### Template Switches

```yaml
template:
  - switch:
      - name: "Guest Mode"
        state: "{{ is_state('input_boolean.guest_mode', 'on') }}"
        turn_on:
          - service: input_boolean.turn_on
            target:
              entity_id: input_boolean.guest_mode
          - service: notify.mobile_app
            data:
              message: "Guest mode enabled"
        turn_off:
          - service: input_boolean.turn_off
            target:
              entity_id: input_boolean.guest_mode
```

### Template Buttons

```yaml
template:
  - button:
      - name: "Restart Server"
        press:
          - service: shell_command.restart_server
          - service: notify.admin
            data:
              message: "Server restart initiated"
```

### Template Numbers

```yaml
template:
  - number:
      - name: "Volume"
        min: 0
        max: 100
        step: 5
        state: "{{ state_attr('media_player.tv', 'volume_level') | float * 100 }}"
        set_value:
          - service: media_player.volume_set
            target:
              entity_id: media_player.tv
            data:
              volume_level: "{{ value / 100 }}"
```

## Groups

### Basic Groups

```yaml
group:
  all_lights:
    name: "All Lights"
    entities:
      - light.living_room
      - light.bedroom
      - light.kitchen
      - light.bathroom

  downstairs_lights:
    name: "Downstairs Lights"
    entities:
      - light.living_room
      - light.kitchen
      - light.hallway
```

### Light Groups (Native)

```yaml
light:
  - platform: group
    name: "All Downstairs Lights"
    unique_id: downstairs_lights
    entities:
      - light.living_room
      - light.kitchen
      - light.hallway
```

### Cover Groups

```yaml
cover:
  - platform: group
    name: "All Blinds"
    unique_id: all_blinds
    entities:
      - cover.living_room_blinds
      - cover.bedroom_blinds
      - cover.kitchen_blinds
```

## Utility Meter

```yaml
utility_meter:
  daily_energy:
    source: sensor.energy_meter_total
    name: "Daily Energy"
    cycle: daily

  monthly_energy:
    source: sensor.energy_meter_total
    name: "Monthly Energy"
    cycle: monthly
    tariffs:
      - peak
      - offpeak

  weekly_water:
    source: sensor.water_meter_total
    name: "Weekly Water"
    cycle: weekly
```

## Counters and Timers

### Counters

```yaml
counter:
  coffee_count:
    name: "Coffees Today"
    initial: 0
    step: 1
    minimum: 0
    maximum: 20
    restore: false

  visitors:
    name: "Visitor Count"
    initial: 0
    step: 1
```

### Timers

```yaml
timer:
  laundry:
    name: "Laundry Timer"
    duration: "01:30:00"
    restore: true

  cooking:
    name: "Cooking Timer"
    duration: "00:30:00"
    icon: mdi:stove
```

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

## Entity Registry

### Finding Entity Information

```yaml
# Developer Tools > States
# Shows all entities with current state and attributes

# Developer Tools > Services
# Test services with entity targets

# Configuration > Entities
# UI for managing entity settings
```

### Entity Naming Best Practices

| Pattern | Example | Description |
|---------|---------|-------------|
| `domain.room_device` | `light.living_room_ceiling` | Room + device type |
| `domain.room_device_number` | `light.kitchen_spot_1` | With numbering |
| `domain.location_type` | `sensor.outdoor_temperature` | Location + measurement |
| `domain.device_measurement` | `sensor.washer_power` | Device + what it measures |

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

### Filter Functions

```yaml
# Count entities in state
{{ states.light | selectattr('state', 'eq', 'on') | list | count }}

# Get entities matching criteria
{{ states.sensor | selectattr('attributes.device_class', 'eq', 'temperature') | list }}

# Average of multiple sensors
{{ expand('group.temperature_sensors') | map(attribute='state') | map('float') | average }}
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Find entity usage | `grep -r "entity_id:" config/ --include="*.yaml"` |
| List customizations | `grep -rA2 "^[a-z_]*\\..*:" config/customize.yaml` |
| Find template sensors | `grep -rB2 "platform: template" config/ --include="*.yaml"` |
| Find groups | `grep -rA5 "^group:" config/ --include="*.yaml"` |
| List domains used | `grep -roh "[a-z_]*\\." config/ --include="*.yaml" \| sort -u` |
