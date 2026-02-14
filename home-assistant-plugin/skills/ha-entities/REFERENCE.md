# Home Assistant Entities - Reference

Detailed reference material for Home Assistant entity management, device classes, template entities, and groups.

## Binary Sensor Device Classes

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

## Sensor Device Classes

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
| `gas` | m3 | Gas consumption |
| `humidity` | % | Relative humidity |
| `illuminance` | lx | Light level |
| `irradiance` | W/m2 | Solar irradiance |
| `moisture` | % | Moisture level |
| `monetary` | currency | Monetary value |
| `nitrogen_dioxide` | ug/m3 | NO2 concentration |
| `nitrogen_monoxide` | ug/m3 | NO concentration |
| `ozone` | ug/m3 | O3 concentration |
| `ph` | - | pH level |
| `pm1` | ug/m3 | PM1 concentration |
| `pm10` | ug/m3 | PM10 concentration |
| `pm25` | ug/m3 | PM2.5 concentration |
| `power` | W | Power consumption |
| `power_factor` | % | Power factor |
| `precipitation` | mm | Precipitation |
| `precipitation_intensity` | mm/h | Precipitation rate |
| `pressure` | hPa | Pressure |
| `reactive_power` | var | Reactive power |
| `signal_strength` | dBm | Signal strength |
| `sound_pressure` | dB | Sound level |
| `speed` | m/s | Speed |
| `sulphur_dioxide` | ug/m3 | SO2 concentration |
| `temperature` | C | Temperature |
| `timestamp` | - | Timestamp |
| `volatile_organic_compounds` | ug/m3 | VOC concentration |
| `voltage` | V | Voltage |
| `volume` | L | Volume |
| `water` | L | Water consumption |
| `weight` | kg | Weight |
| `wind_speed` | m/s | Wind speed |

## Extended Template Entity Examples

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

## Filter Functions

```yaml
# Count entities in state
{{ states.light | selectattr('state', 'eq', 'on') | list | count }}

# Get entities matching criteria
{{ states.sensor | selectattr('attributes.device_class', 'eq', 'temperature') | list }}

# Average of multiple sensors
{{ expand('group.temperature_sensors') | map(attribute='state') | map('float') | average }}
```
