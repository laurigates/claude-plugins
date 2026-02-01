---
model: haiku
created: 2025-02-01
modified: 2025-02-01
reviewed: 2025-02-01
name: ha-configuration
description: |
  Home Assistant YAML configuration management. Use when editing configuration.yaml,
  setting up integrations, configuring secrets, managing packages, or troubleshooting
  Home Assistant configuration issues. Covers core configuration patterns and best practices.
allowed-tools: Read, Edit, Write, Grep, Glob, TodoWrite
---

# Home Assistant Configuration

## When to Use This Skill

| Use this skill when... | Use ha-automations instead when... |
|------------------------|-----------------------------------|
| Editing configuration.yaml | Creating automation rules |
| Setting up integrations | Writing automation triggers/actions |
| Managing secrets.yaml | Debugging automation logic |
| Organizing with packages | Working with automation blueprints |
| Troubleshooting config errors | Setting up device triggers |

## Core Configuration Files

| File | Purpose |
|------|---------|
| `configuration.yaml` | Main configuration entry point |
| `secrets.yaml` | Sensitive values (passwords, API keys, tokens) |
| `automations.yaml` | Automation rules (usually UI-managed) |
| `scripts.yaml` | Reusable script sequences |
| `scenes.yaml` | Scene definitions |
| `customize.yaml` | Entity customizations |
| `packages/*.yaml` | Modular configuration packages |

## Configuration Structure

### Basic configuration.yaml

```yaml
homeassistant:
  name: Home
  unit_system: metric
  time_zone: Europe/Helsinki
  currency: EUR
  country: FI

  # External files
  customize: !include customize.yaml
  packages: !include_dir_named packages/

# Core integrations
default_config:

# Text-to-speech
tts:
  - platform: google_translate

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
```

### Secrets Management

**secrets.yaml:**
```yaml
# API keys
openweathermap_api_key: "abc123def456"
spotify_client_id: "your_client_id"
spotify_client_secret: "your_client_secret"

# Database
recorder_db_url: "postgresql://user:pass@localhost/hass"

# MQTT
mqtt_username: "homeassistant"
mqtt_password: "secure_password"

# Network
latitude: 60.1699
longitude: 24.9384
```

**Reference in configuration.yaml:**
```yaml
weather:
  - platform: openweathermap
    api_key: !secret openweathermap_api_key

recorder:
  db_url: !secret recorder_db_url
```

## Include Directives

| Directive | Description | Example |
|-----------|-------------|---------|
| `!include` | Include single file | `!include automations.yaml` |
| `!include_dir_list` | Include files as list items | `!include_dir_list sensors/` |
| `!include_dir_named` | Include files as named mappings | `!include_dir_named packages/` |
| `!include_dir_merge_list` | Merge files into single list | `!include_dir_merge_list automations/` |
| `!include_dir_merge_named` | Merge files into single mapping | `!include_dir_merge_named integrations/` |
| `!secret` | Reference from secrets.yaml | `!secret api_key` |
| `!env_var` | Environment variable | `!env_var DB_PASSWORD` |

## Package Organization

Packages allow modular configuration by domain:

**packages/climate.yaml:**
```yaml
climate_package:
  sensor:
    - platform: template
      sensors:
        average_indoor_temp:
          friendly_name: "Average Indoor Temperature"
          unit_of_measurement: "°C"
          value_template: >-
            {{ (states('sensor.living_room_temp') | float +
                states('sensor.bedroom_temp') | float) / 2 | round(1) }}

  automation:
    - alias: "Climate - AC Auto Off"
      trigger:
        - platform: numeric_state
          entity_id: sensor.average_indoor_temp
          below: 22
      action:
        - service: climate.turn_off
          target:
            entity_id: climate.living_room_ac

  script:
    climate_cool_down:
      alias: "Cool Down House"
      sequence:
        - service: climate.set_temperature
          target:
            entity_id: climate.living_room_ac
          data:
            temperature: 20
            hvac_mode: cool
```

**packages/presence.yaml:**
```yaml
presence_package:
  input_boolean:
    guest_mode:
      name: "Guest Mode"
      icon: mdi:account-multiple

  binary_sensor:
    - platform: template
      sensors:
        anyone_home:
          friendly_name: "Anyone Home"
          device_class: presence
          value_template: >-
            {{ is_state('person.user1', 'home') or
               is_state('person.user2', 'home') or
               is_state('input_boolean.guest_mode', 'on') }}
```

## Common Integration Patterns

### MQTT Configuration

```yaml
mqtt:
  broker: !secret mqtt_broker
  port: 1883
  username: !secret mqtt_username
  password: !secret mqtt_password
  discovery: true
  discovery_prefix: homeassistant

  sensor:
    - name: "Outdoor Temperature"
      state_topic: "sensors/outdoor/temperature"
      unit_of_measurement: "°C"
      device_class: temperature
      value_template: "{{ value_json.temperature }}"
```

### REST Sensors

```yaml
sensor:
  - platform: rest
    name: "GitHub Stars"
    resource: https://api.github.com/repos/home-assistant/core
    value_template: "{{ value_json.stargazers_count }}"
    scan_interval: 3600
    headers:
      Authorization: !secret github_token
```

### Template Sensors

```yaml
template:
  - sensor:
      - name: "Sun Elevation"
        unit_of_measurement: "°"
        state: "{{ state_attr('sun.sun', 'elevation') | round(1) }}"

      - name: "Daylight Hours"
        unit_of_measurement: "hours"
        state: >-
          {% set sunrise = as_timestamp(state_attr('sun.sun', 'next_rising')) %}
          {% set sunset = as_timestamp(state_attr('sun.sun', 'next_setting')) %}
          {{ ((sunset - sunrise) / 3600) | round(1) }}

  - binary_sensor:
      - name: "Workday"
        state: "{{ now().weekday() < 5 }}"
```

### Input Helpers

```yaml
input_boolean:
  vacation_mode:
    name: "Vacation Mode"
    icon: mdi:airplane

input_number:
  target_temperature:
    name: "Target Temperature"
    min: 16
    max: 28
    step: 0.5
    unit_of_measurement: "°C"
    icon: mdi:thermometer

input_select:
  house_mode:
    name: "House Mode"
    options:
      - Home
      - Away
      - Sleep
      - Guest
    icon: mdi:home

input_text:
  notification_message:
    name: "Custom Notification"
    max: 255

input_datetime:
  alarm_time:
    name: "Alarm Time"
    has_date: false
    has_time: true
```

## Configuration Validation

### Check Configuration

```bash
# Docker/Container
docker exec homeassistant hass --script check_config

# Home Assistant OS
ha core check

# Supervised
hassio homeassistant check

# Python venv
hass --script check_config -c /path/to/config
```

### Common Validation Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `found undefined alias` | Missing `!secret` value | Add to secrets.yaml |
| `could not determine a constructor` | Invalid YAML syntax | Check indentation |
| `duplicate key` | Same key defined twice | Remove duplicate |
| `Platform not found` | Missing integration | Install via UI/HACS |

## Recorder Configuration

```yaml
recorder:
  db_url: !secret recorder_db_url
  purge_keep_days: 10
  commit_interval: 1

  exclude:
    domains:
      - automation
      - updater
    entity_globs:
      - sensor.weather_*
    entities:
      - sun.sun
      - sensor.date

  include:
    domains:
      - sensor
      - binary_sensor
      - switch
```

## Logger Configuration

```yaml
logger:
  default: warning
  logs:
    homeassistant.core: info
    homeassistant.components.mqtt: debug
    custom_components.my_integration: debug
    # Reduce noise
    homeassistant.components.websocket_api: error
```

## Lovelace Dashboard (YAML Mode)

```yaml
# configuration.yaml
lovelace:
  mode: yaml
  resources:
    - url: /hacsfiles/button-card/button-card.js
      type: module
  dashboards:
    lovelace-home:
      mode: yaml
      filename: dashboards/home.yaml
      title: Home
      icon: mdi:home
      show_in_sidebar: true
```

## Quick Reference

### YAML Tips

| Pattern | Example |
|---------|---------|
| Multi-line string | `value: >-` or `value: \|-` |
| List item | `- item` |
| Inline list | `[item1, item2]` |
| Comment | `# comment` |
| Anchor | `&anchor_name` |
| Reference | `*anchor_name` |
| Merge | `<<: *anchor_name` |

### Template Syntax

| Function | Example |
|----------|---------|
| State value | `states('sensor.temp')` |
| State attribute | `state_attr('sun.sun', 'elevation')` |
| Convert to float | `states('sensor.temp') \| float` |
| Round | `value \| round(1)` |
| Default value | `states('sensor.x') \| default('unknown')` |
| Timestamp | `as_timestamp(now())` |
| Time delta | `now() - timedelta(hours=1)` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Validate config | `docker exec homeassistant hass --script check_config 2>&1 \| head -50` |
| Find entity usage | `grep -r "entity_id:" config/ --include="*.yaml"` |
| Find secret refs | `grep -r "!secret" config/ --include="*.yaml"` |
| List packages | `ls -la config/packages/` |
| Check YAML syntax | `python3 -c "import yaml; yaml.safe_load(open('file.yaml'))"` |
