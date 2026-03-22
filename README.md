# Finnleo SaunaLogic2 — Home Assistant Integration Guide

**The Finnleo SaunaLogic2 is a Tuya OEM device.** This means you can control it from Home Assistant using existing Tuya integrations — no custom code required.

This repository documents the reverse engineering journey that led to this discovery, provides the complete device specification (data points), and includes a ready-to-use device definition for the [`tuya_local`](https://github.com/make-all/tuya_local) HACS integration.

## Quick Start

If you just want to get your SaunaLogic2 working with Home Assistant:

1. **Pair your sauna to the [Smart Life](https://apps.apple.com/us/app/smart-life-smart-living/id1115101477) app** (not the SaunaLogic app — see [why](#the-oem-problem))
2. **Install [tuya_local](https://github.com/make-all/tuya_local)** via HACS
3. **Copy [`tylohelo_sl2_sauna.yaml`](#device-definition)** to your `custom_components/tuya_local/devices/` directory
4. **Add the device** in tuya_local using your device ID and local key (create a free [Tuya IoT developer account](https://iot.tuya.com/), create a Cloud project with the Western America data center, link your Smart Life account under Devices, and find your sauna's device ID and local key. Alternatively, use `python -m tinytuya wizard` to extract these values.)
5. **Restart Home Assistant**

You'll get:
- **Climate entity** — heater on/off, target temperature (25-194°F), current temperature
- **Light select** — Off, White, Red, Green, Blue, Yellow, Aqua, Purple, Rainbow
- **Timer sensor** — session countdown in minutes
- **Diagnostic sensors** — sauna mode, run state, Bluetooth status

## The OEM Problem

The SaunaLogic app is a white-label Tuya app (appId 15909) that creates an **isolated account** separate from the standard Smart Life / Tuya Smart ecosystem. Even if you use the same email address, the accounts don't share devices.

To get your sauna's local key (required for local control), you need to pair it to the **Smart Life** app instead. This is a one-time step:

1. Put the SL2 in pairing mode: press and hold the Bluetooth button until you hear a beep, release, press and hold again until a second beep. Display shows "CON1".
2. The sauna creates a `SmartLife-XXXX` WiFi hotspot.
3. In Smart Life, go to Add Device → choose any device type → select **AP Mode** (not auto-scan).
4. Enter your home WiFi credentials, connect to the SmartLife hotspot, return to the app.
5. The device appears in Smart Life and in your Tuya developer project.

**Note:** Only one app can "own" the device at a time. Pairing to Smart Life disconnects it from the SaunaLogic app.

## Data Points

The SaunaLogic2 exposes 10 Tuya data points. Only 4 are registered in the Tuya cloud product definition — the rest were discovered through local protocol probing.

### Registered DPs (visible in Tuya Cloud API)

| DP | Code | Type | Range | Description |
|---|---|---|---|---|
| 1 | `switch` | Boolean | true/false | Heater power on/off |
| 2 | `temp_set` | Integer | 25-194 (°F) | Target temperature |
| 3 | `temp_current` | Integer | 0-210 (°F) | Current temperature |
| 10 | `countdown_left` | Integer | 0-1440 (min) | Session timer remaining |

### Hidden DPs (discovered via local probing)

| DP | Type | Values | Description |
|---|---|---|---|
| 4 | String | `ONLY_TRAD` | Sauna mode |
| 9 | Integer | 0, 1 | Delay-related flag (1=normal, 0=delay set) |
| 11 | Integer | 0 | Unknown |
| 101 | Integer | 0-8 | Light color mode (see table below) |
| 103 | Boolean | true/false | Bluetooth audio on/off |
| 105 | Integer | 1, 2 | Sauna state (1=idle, 2=running) |

### Light Color Modes (DP 101)

| Value | Color |
|-------|-------|
| 0 | Off |
| 1 | White |
| 2 | Red |
| 3 | Green |
| 4 | Blue |
| 5 | Yellow |
| 6 | Aqua |
| 7 | Purple |
| 8 | Rainbow |

## Device Definition

Copy this file to `/config/custom_components/tuya_local/devices/tylohelo_sl2_sauna.yaml`:

```yaml
name: Sauna
products:
  - id: acl5qrawgmjajabn
    manufacturer: TyloHelo
    model: SaunaLogic2
entities:
  - entity: climate
    translation_only_key: heater
    dps:
      - id: 1
        name: hvac_mode
        type: boolean
        mapping:
          - dps_val: true
            value: heat
          - dps_val: false
            value: "off"
      - id: 2
        name: temperature
        type: integer
        unit: F
        range:
          min: 25
          max: 194
      - id: 3
        name: current_temperature
        type: integer
  - entity: select
    name: Light
    icon: "mdi:lightbulb"
    dps:
      - id: 101
        name: option
        type: integer
        mapping:
          - dps_val: 0
            value: "Off"
          - dps_val: 1
            value: White
          - dps_val: 2
            value: Red
          - dps_val: 3
            value: Green
          - dps_val: 4
            value: Blue
          - dps_val: 5
            value: Yellow
          - dps_val: 6
            value: Aqua
          - dps_val: 7
            value: Purple
          - dps_val: 8
            value: Rainbow
  - entity: sensor
    name: Timer remaining
    class: duration
    dps:
      - id: 10
        name: sensor
        type: integer
        unit: min
  - entity: sensor
    name: Sauna mode
    category: diagnostic
    dps:
      - id: 4
        name: sensor
        type: string
        optional: true
  - entity: sensor
    name: Delay flag
    category: diagnostic
    dps:
      - id: 9
        name: sensor
        type: integer
        optional: true
  - entity: sensor
    name: Bluetooth
    category: diagnostic
    dps:
      - id: 103
        name: sensor
        type: boolean
        optional: true
  - entity: sensor
    name: Sauna state
    category: diagnostic
    dps:
      - id: 105
        name: sensor
        type: integer
        optional: true
```

## Known Limitations

- **Timer cannot be set via Tuya DPs** — it auto-sets to 60 minutes when the heater is turned on. The timer duration may only be configurable from the physical panel.
- **Delay start countdown is not exposed** — Setting a delay from the panel changes DP 9, but the countdown value itself is not reported via any known DP.
- **Firmware minimum temperature** — Setting the target below ~119°F may be overridden by the device firmware.
- **Aggressive DP probing can lock out the device** — Requesting many unknown DPs at once caused the device to stop accepting local connections until power-cycled. Probe gently.

## Applicability

This was tested on a Finnleo SaunaLogic2, but it likely works for other Sauna360-family controllers using the same Tuya product ID (`acl5qrawgmjajabn`). Sauna360 brands include:
- **Finnleo**
- **Tylo**
- **Helo**
- **Amerec**
- **Kastor**

If you have a different Sauna360 sauna with a SaunaLogic2 controller, this device definition should work. If your sauna uses a different Tuya product ID, the DP mapping may still be the same — just add your product ID to the `products` list in the YAML.

## The Full Story

Read the complete reverse engineering journey in [docs/journey.md](docs/journey.md) — including the part where we found the sauna on our first network scan, dismissed it as a smart plug, and then spent hours looking for it elsewhere.

## Research

- [APK Decompilation Findings](docs/research/apk_decompilation_findings.md) — How we discovered SaunaLogic is Tuya
- [Device Specification](docs/research/bjorn_device_spec.md) — Complete DP mapping with test results
- [Network Discovery](docs/research/network_scan_and_tuya_discovery.md) — How to find your sauna on the network
- [Huum UKU Reverse Engineering](docs/research/huum_uku_reverse_engineering.md) — The reference that inspired this project
- [Huum HA Integration Analysis](docs/research/huum_ha_integration_analysis.md) — Lessons learned from the official Huum integration
- [Sauna RE Landscape](docs/research/sauna_re_landscape.md) — Every sauna HA integration ever built
- [Original Reverse Engineering Plan](reverse_engineering_guide.md) — The plan before we discovered it was Tuya

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

- [Kaur Palang](https://kaurpalang.com/posts/invading-the-sauna/) for the Huum UKU reverse engineering that showed this was possible
- [tuya_local](https://github.com/make-all/tuya_local) for the HACS integration that makes this work with zero custom code
- [tinytuya](https://github.com/jasonacox/tinytuya) for the device discovery and Tuya protocol tools
