# Home Assistant Plugin

Home Assistant configuration management for Claude Code - YAML configuration, automations, scripts, scenes, and entity management.

## Overview

This plugin provides skills and commands for managing Home Assistant installations through configuration files. It covers:

- Core YAML configuration patterns
- Automation rules, triggers, conditions, and actions
- Entity management and customization
- Template entities and sensors
- Scripts, scenes, and groups
- Configuration validation

## Skills

| Skill | Description |
|-------|-------------|
| `ha-configuration` | Core YAML configuration, secrets, packages, integrations |
| `ha-automations` | Automation rules, triggers, conditions, actions, scripts, scenes |
| `ha-entities` | Entity domains, device classes, customization, template entities |

## Commands

| Command | Description |
|---------|-------------|
| `/ha:validate` | Validate YAML configuration files for syntax and structure errors |

## Usage Examples

### Configuration Management

Ask Claude to help with:

- "Add MQTT configuration to my Home Assistant setup"
- "Create a package for climate control"
- "Set up secrets management for my API keys"
- "Configure the recorder to exclude noisy entities"

### Automation Creation

Ask Claude to help with:

- "Create a motion-activated light automation"
- "Set up a presence-based thermostat automation"
- "Write an automation that sends notifications when the door is left open"
- "Create a sunrise/sunset based lighting automation"

### Entity Management

Ask Claude to help with:

- "Create a template sensor for average indoor temperature"
- "Set up a binary sensor to detect if anyone is home"
- "Configure entity customizations for my lights"
- "Create a group for all downstairs lights"

### Validation

```
/ha:validate
/ha:validate /path/to/config
```

## Configuration File Structure

```
config/
├── configuration.yaml      # Main configuration
├── secrets.yaml           # Sensitive values
├── automations.yaml       # Automation rules
├── scripts.yaml           # Reusable scripts
├── scenes.yaml            # Scene definitions
├── customize.yaml         # Entity customizations
└── packages/              # Modular configuration
    ├── climate.yaml
    ├── presence.yaml
    └── notifications.yaml
```

## Key Concepts

### Include Directives

| Directive | Usage |
|-----------|-------|
| `!include file.yaml` | Include single file |
| `!include_dir_named packages/` | Include directory as named mappings |
| `!include_dir_merge_list automations/` | Merge directory into list |
| `!secret key_name` | Reference from secrets.yaml |

### Automation Structure

```yaml
automation:
  - alias: "Example"
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

### Template Sensors

```yaml
template:
  - sensor:
      - name: "Average Temperature"
        unit_of_measurement: "°C"
        state: >-
          {{ (states('sensor.room1') | float +
              states('sensor.room2') | float) / 2 }}
```

## Installation

```bash
/plugin install home-assistant-plugin@laurigates-plugins
```

## License

MIT
