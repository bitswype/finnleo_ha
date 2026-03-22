# Björn — TyloHelo SL2 Tuya Device Specification

## Device Identity
| Field | Value |
|-------|-------|
| Device Name | Björn |
| Model | Sauna |
| Product Name | TyloHelo SL2 |
| Product ID | acl5qrawgmjajabn |
| Device ID | <your-device-id> |
| Tuya Category | `dr` |
| Protocol Version | 3.3 |
| Local IP | <your-sauna-ip> |
| Local Port | 6668 |
| MAC Address | xx:xx:xx:xx:xx:xx |
| Chip | Espressif (ESP32/ESP8266) |

## Data Points

### Controllable (Functions)

| DP Code | Type | Min | Max | Step | Unit | Description |
|---------|------|-----|-----|------|------|-------------|
| `switch` | Boolean | — | — | — | — | Sauna power on/off |
| `temp_set` | Integer | 25 | 194 | 1 | °F | Target temperature |

### Read-Only (Status)

| DP Code | Type | Min | Max | Step | Unit | Description |
|---------|------|-----|-----|------|------|-------------|
| `temp_current` | Integer | 0 | 210 | 1 | °F | Current temperature reading |
| `countdown_left` | Integer | 0 | 1440 | 1 | minutes | Timer countdown remaining |

### Chinese Names (from Tuya API)
| DP Code | Chinese Name | English Translation |
|---------|-------------|-------------------|
| `switch` | 开关 | Switch |
| `temp_set` | 温度设置 | Temperature Setting |
| `temp_current` | 当前温度 | Current Temperature |
| `countdown_left` | 倒计时剩余时间 | Countdown Remaining Time |

## Sample Status Response
```json
{
  "switch": false,
  "temp_set": 194,
  "temp_current": 41,
  "countdown_left": 0
}
```

## Hidden Data Points (discovered via local probing)

These DPs are NOT registered in the Tuya cloud product definition but ARE
reported by the device firmware when probed via tuya_local.

### Light Control

| DP Code | DP ID | Type | Description |
|---------|-------|------|-------------|
| — | 101 | Integer (0-8) | Light color mode |

| Value | Mode |
|-------|------|
| 0 | Off |
| 1 | White |
| 2 | Red |
| 3 | Green |
| 4 | Blue |
| 5 | Yellow |
| 6 | Aqua |
| 7 | Purple |
| 8 | Rainbow |

### Other Hidden DPs

| DP ID | Type | Observed Values | Description |
|-------|------|-----------------|-------------|
| 4 | String | `ONLY_TRAD` | Sauna mode (traditional) |
| 9 | Integer | `0`, `1` | Delay-related flag (1=no delay, 0=delay was set). Does NOT reset to 1 when sauna is turned off. |
| 11 | Integer | `0` | Unknown (always 0) |
| 103 | Boolean | `True`/`False` | Bluetooth audio on/off |
| 105 | Integer | `1`, `2` | Sauna state (1=idle, 2=running) |

## Verified Write Commands (tested 2026-03-22)

All write commands tested with physical verification at the sauna:

| Command | Method | Result |
|---------|--------|--------|
| Turn heater on | `climate.set_hvac_mode` → heat | Relay clicked, felt warmth |
| Turn heater off | `climate.set_hvac_mode` → off | Relay clicked off |
| Set temperature | `climate.set_temperature` → 100°F | Display showed 119°F (device has minimum) |
| Light white | `select.select_option` → White | Confirmed visually |
| Light red | `select.select_option` → Red | Confirmed visually |
| Light rainbow | `select.select_option` → Rainbow | Confirmed visually, cycling colors |
| Light off | `select.select_option` → Off | Confirmed visually |

## Two-Way Communication (tested 2026-03-22)

Physical changes on the sauna controller panel are reflected in HA in real-time:

| Physical Action | HA Detected |
|----------------|-------------|
| Turn heater on from panel | `climate.bjorn` → heat |
| Change target temp on panel | `temperature` attribute updated |
| Timer countdown | `sensor.bjorn_timer_remaining` counts down |
| Light on (red) from panel | `select.bjorn_light` → Red |
| Bluetooth on from panel | `sensor.bjorn_dp_103` → True |
| Set delay from panel | `sensor.bjorn_dp_9` → 0 |
| Turn off from panel | `climate.bjorn` → off, timer → 0 |

## Notes

- Temperature values are in **Fahrenheit** (target range 25–194°F = ~-4–90°C)
- The `countdown_left` max of 1440 minutes = 24 hours, but the SaunaLogic app limits sessions to 60 minutes. The hardware safety timer is likely the actual limiter.
- When setting temperature to 100°F, the device reported 119°F — there may be a firmware-enforced minimum temperature.
- Timer auto-sets to 60 minutes when the heater is turned on via Tuya. The timer value cannot be set independently via known DPs.
- `switch` and `temp_set` are controllable via the Tuya cloud API. Light (DP 101) and Bluetooth (DP 103) are controllable locally but not registered in the cloud product definition.
- **Delay start countdown is NOT exposed via any known Tuya DP.** Setting a delay from the panel changes DP 9 from 1→0, and the display shows the countdown, but the countdown value itself is not reported. The delay may use an undiscovered DP or be handled entirely in the controller firmware.
- The Tuya category `dr` is not a standard well-known category — it may be a custom OEM category.
- DP 4 value "ONLY_TRAD" suggests the device supports a "traditional" sauna mode. Other modes may exist for infrared or combo saunas in the Sauna360 product line.
- **Aggressive DP discovery (requesting many unknown DPs at once) caused the device to stop accepting local connections.** A power cycle was required to recover. Future DP discovery should be done one at a time.

## tuya_local Device Definition

A custom device definition was created at:
`/config/custom_components/tuya_local/devices/tylohelo_sl2_sauna.yaml`

```yaml
name: Sauna
products:
  - id: acl5qrawgmjajabn
    manufacturer: TyloHelo
    model: SaunaLogic2
entities:
  - entity: climate        # DP 1 (power), DP 2 (target temp), DP 3 (current temp)
  - entity: select          # DP 101 (light color mode)
  - entity: sensor          # DP 10 (timer countdown)
  - entity: sensor          # DP 4 (sauna mode, diagnostic)
  - entity: sensor          # DP 103 (bluetooth, diagnostic)
  - entity: sensor          # DP 105 (sauna state, diagnostic)
```

## Configuration

```
Device ID: <your-device-id>
Local Key: <your-local-key>
IP Address: <your-sauna-ip>
Protocol Version: 3.3
```

## Discovery Timeline
1. Network scan found ESP32 at <your-sauna-ip> with Tuya protocol on port 6668
2. We dismissed it as "just a Tuya plug" — laughable mistake
3. APK decompilation revealed SaunaLogic is a Tuya OEM app (appId 15909)
4. SaunaLogic app confirmed device MAC = xx:xx:xx:xx:xx:xx = Björn = <your-sauna-ip>
5. Tried to link OEM account to Tuya developer project — blocked by OEM isolation
6. Re-paired device to Smart Life app to access Tuya developer project
7. Tuya Cloud API returned 4 registered DPs (switch, temp_set, temp_current, countdown_left)
8. Local key obtained for cloud-free local control via Tuya protocol v3.3
9. Created custom tuya_local device definition with probe sensors
10. Discovered 5 hidden DPs: light (101), sauna mode (4), bluetooth (103), state (105), unknown (9)
11. Mapped all 9 light color values (0-8) by toggling each from the Smart Life app
