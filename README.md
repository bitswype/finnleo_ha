<!--
Copyright 2026 Chris Keeser

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# Finnleo SaunaLogic2 — Home Assistant Integration Guide

**The Finnleo SaunaLogic2 is a Tuya OEM device.** This means you can control it from Home Assistant using existing Tuya integrations — no custom code required.

This repository documents the reverse engineering journey that led to this discovery, provides the complete device specification (data points), and includes a ready-to-use device definition for the [`tuya_local`](https://github.com/make-all/tuya_local) HACS integration.

---

## Table of Contents

- [Quick Start](#quick-start)
- [The OEM Problem](#the-oem-problem)
- [Pairing to Smart Life](#pairing-to-smart-life)
- [Setting Up a Tuya Developer Account](#setting-up-a-tuya-developer-account)
- [Integration Option 1: tuya_local (Local, Recommended)](#integration-option-1-tuya_local-local-recommended)
- [Integration Option 2: Tuya Cloud (Official Integration)](#integration-option-2-tuya-cloud-official-integration)
- [Data Points](#data-points)
- [Device Definition](#device-definition)
- [Known Limitations](#known-limitations)
- [Applicability](#applicability)
- [The Full Story](#the-full-story)
- [Research](#research)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## Quick Start

1. **Pair your sauna to the [Smart Life](https://apps.apple.com/us/app/smart-life-smart-living/id1115101477) app** (not the SaunaLogic app — see [why](#the-oem-problem))
2. **Set up a [Tuya developer account](#setting-up-a-tuya-developer-account)** to get your device ID and local key
3. **Choose your integration** — [tuya_local (local)](#integration-option-1-tuya_local-local-recommended) or [Tuya Cloud](#integration-option-2-tuya-cloud-official-integration)
4. **Restart Home Assistant**

You'll get:
- **Climate entity** — heater on/off, target temperature (25-194°F), current temperature
- **Light select** — Off, White, Red, Green, Blue, Yellow, Aqua, Purple, Rainbow
- **Timer sensor** — session countdown in minutes
- **Diagnostic sensors** — sauna mode, run state, Bluetooth status

---

## The OEM Problem

The SaunaLogic app is a white-label Tuya app (appId 15909) that creates an **isolated account** separate from the standard Smart Life / Tuya Smart ecosystem. Even if you use the same email address, the accounts don't share devices.

This means you cannot link your SaunaLogic app to a Tuya developer project. You cannot scan the developer console's QR code with the SaunaLogic app. You cannot share the device from SaunaLogic to Smart Life.

The solution is to **pair the sauna directly to the Smart Life app**, bypassing the SaunaLogic app entirely.

**Note:** Only one app can "own" the device at a time. Pairing to Smart Life disconnects it from the SaunaLogic app. You will lose the SaunaLogic app's custom sauna UI, but you gain full Home Assistant control — which is the whole point.

---

## Pairing to Smart Life

### Prerequisites
- The **Smart Life** app installed on your phone ([iOS](https://apps.apple.com/us/app/smart-life-smart-living/id1115101477) / [Android](https://play.google.com/store/apps/details?id=com.tuya.smartlife))
- A Smart Life account (create one in the app if you don't have one)
- Your phone connected to your **2.4 GHz WiFi network** (the SL2 does not support 5 GHz)
- Physical access to the SaunaLogic2 control panel

### Steps

1. **Put the SL2 in pairing mode:**
   - Press and hold the **Bluetooth button** on the control panel until you hear **one beep**, then release
   - Press and hold the Bluetooth button **again** until you hear a **second beep**, then release
   - The display should show **"CON1"** — the sauna is now in pairing mode
   - The sauna creates a WiFi hotspot named `SmartLife-XXXX`

2. **Add the device in Smart Life:**
   - Open Smart Life → tap **"+"** → **"Add Device"**
   - Select any device category (e.g., "Socket (Wi-Fi)" — the category doesn't matter)
   - **Important:** Do NOT use auto-scan. Look for **"AP Mode"**, **"Compatible Mode (AP)"**, or **"Hotspot Mode"** — it's often a small text link near the bottom of the screen. You must select this mode.
   - Enter your **home WiFi network name (SSID)** and **password** (must be 2.4 GHz)
   - The app will tell you to connect to the `SmartLife-XXXX` hotspot

3. **Connect to the hotspot:**
   - Go to your phone's WiFi settings
   - Connect to the `SmartLife-XXXX` network (it will show as unsecured)
   - Return to the Smart Life app

4. **Wait for pairing to complete:**
   - The app will configure the device (this takes about 30-60 seconds)
   - You should see "Device added successfully"
   - Name your device and tap Done

### Troubleshooting
- **"Network is unavailable"** — Make sure you're connected to the `SmartLife-XXXX` hotspot, not your home WiFi
- **Can't find AP Mode** — Try a different device category, or try the **Tuya Smart** app (same account system, sometimes shows more options)
- **Pairing times out** — The sauna's pairing mode lasts about 2 minutes. If it times out, repeat the two-press Bluetooth button sequence to re-enter pairing mode
- **"Con L" on the display** — WiFi configuration error. Power cycle the sauna (breaker off for 10 seconds, then back on) and try again

---

## Setting Up a Tuya Developer Account

You need a Tuya IoT Platform developer account to get your device's **device ID** and **local key**. Both are required for the `tuya_local` integration, and the device ID is needed for the cloud integration as well. This is free.

### Step 1: Create an Account

1. Go to [iot.tuya.com](https://iot.tuya.com/) and click **"Start Free Trial"** or **"Sign Up"**
2. Create an account using your email address
3. Complete the developer profile (select "Smart Home" for industry, "Personal" for company type)

### Step 2: Create a Cloud Project

1. Go to **Cloud** → **Development** → **Create Cloud Project**
2. Fill in:
   - **Project Name:** Anything you like (e.g., "Home Assistant")
   - **Industry:** Smart Home
   - **Development Method:** Smart Home
   - **Data Center:** Select the data center for your region. For the US, choose **Western America**. For Europe, choose **Central Europe**. You can select multiple data centers.
3. Click **Create**

### Step 3: Subscribe to APIs

After creating the project, you need to subscribe to API services:

1. Go to your project → **Service API** tab
2. Click **"Go to Authorize"** or **"Subscribe"**
3. Subscribe to (at minimum):
   - **IoT Core** — required for device management
   - **Authorization Token Management** — required for API authentication
   - **Smart Home Basic Service** — required for home/device operations
4. These are free for personal/development use

### Step 4: Link Your Smart Life Account

1. Go to your project → **Devices** tab
2. Click **"Link Tuya App Account"** → **"Add App Account"**
3. A QR code will appear
4. Open the **Smart Life** app on your phone → tap **"Me"** tab → tap the **scan icon** (top right) → scan the QR code
5. Confirm the linking in the app
6. Your devices (including the sauna) should now appear in the Devices tab

### Step 5: Find Your Device ID and Local Key

1. In the **Devices** tab, you should see your sauna listed
2. Click on the device to see its **Device ID**
3. The **local key** is shown in the device details

**Alternative method using tinytuya:**

If you prefer the command line, [tinytuya](https://github.com/jasonacox/tinytuya) can extract all device IDs and local keys:

```bash
pip install tinytuya
python -m tinytuya wizard
```

The wizard will ask for your Tuya developer project's **Access ID** and **Access Secret** (found on your project's Overview page), then pull all your devices and their local keys.

**Keep your local key safe.** Anyone with your device ID and local key can control your sauna on your local network.

---

## Integration Option 1: tuya_local (Local, Recommended)

[tuya_local](https://github.com/make-all/tuya_local) is a HACS integration that communicates with Tuya devices **directly on your local network** — no cloud connection required. This is the recommended approach for reliability and privacy.

### Setup

1. Install **tuya_local** from HACS (search for "Tuya Local")
2. Copy the [device definition YAML](#device-definition) below to:
   ```
   /config/custom_components/tuya_local/devices/tylohelo_sl2_sauna.yaml
   ```
3. Restart Home Assistant
4. Go to **Settings** → **Devices & Services** → **Tuya Local** → **Add Device**
5. Enter your sauna's:
   - **IP Address** (find this in your router's DHCP table — look for a device with an Espressif MAC address or hostname starting with `ESP_` or `SmartLife`)
   - **Device ID** (from the Tuya developer console or tinytuya)
   - **Local Key** (from the Tuya developer console or tinytuya)
   - **Protocol Version:** 3.3
6. The device type should be detected as "Sauna" — select it
7. Your sauna entities will appear

### What You Get

| Entity | Type | Description |
|--------|------|-------------|
| `climate.bjorn` | Climate | Heater on/off, target temperature, current temperature |
| `select.bjorn_light` | Select | Light color mode (9 options) |
| `sensor.bjorn_timer_remaining` | Sensor | Session countdown (minutes) |
| `sensor.bjorn_sauna_mode` | Sensor | Sauna mode (diagnostic) |
| `sensor.bjorn_sauna_state` | Sensor | Run state: 1=idle, 2=running (diagnostic) |
| `sensor.bjorn_bluetooth` | Sensor | Bluetooth audio status (diagnostic) |
| `sensor.bjorn_delay_flag` | Sensor | Delay flag (diagnostic) |

(Entity names will reflect whatever you named your sauna in Smart Life.)

---

## Integration Option 2: Tuya Cloud (Official Integration)

The [official Tuya integration](https://www.home-assistant.io/integrations/tuya/) in Home Assistant uses Tuya's cloud API. This is simpler to set up but depends on Tuya's cloud servers being available.

### Setup

1. Complete the [Tuya developer account setup](#setting-up-a-tuya-developer-account) above
2. In Home Assistant, go to **Settings** → **Devices & Services** → **Add Integration** → search for **"Tuya"**
3. Enter your Tuya developer project's:
   - **Access ID** (from your project's Overview page)
   - **Access Secret** (from your project's Overview page)
   - **Account:** Your Smart Life email/phone number
   - **Password:** Your Smart Life password
   - **Country Code:** Your country code (e.g., `1` for US)
4. Your devices should appear

### Limitations of the Cloud Integration

- **Depends on Tuya's cloud** — if Tuya's servers are down, you lose control
- **Only sees the 4 registered DPs** — the cloud integration can only control power (DP 1) and target temperature (DP 2), and read current temperature (DP 3) and timer (DP 10)
- **No light control** — DP 101 (lighting) is a hidden/unregistered DP that the cloud integration cannot see or control
- **No Bluetooth, sauna mode, or state sensors** — these are also hidden DPs
- **Higher latency** — commands go through Tuya's cloud servers rather than directly on your LAN

For full functionality (especially lights), use [tuya_local](#integration-option-1-tuya_local-local-recommended) instead.

---

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

---

## Device Definition

Copy this file to `/config/custom_components/tuya_local/devices/tylohelo_sl2_sauna.yaml`:

```yaml
# Copyright 2026 Chris Keeser
# SPDX-License-Identifier: Apache-2.0

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

---

## Known Limitations

- **Timer cannot be set via Tuya DPs** — it auto-sets to 60 minutes when the heater is turned on. The timer duration may only be configurable from the physical panel.
- **Delay start countdown is not exposed** — Setting a delay from the panel changes DP 9, but the countdown value itself is not reported via any known DP.
- **Firmware minimum temperature** — Setting the target below ~119°F may be overridden by the device firmware.
- **Aggressive DP probing can lock out the device** — Requesting many unknown DPs at once caused the device to stop accepting local connections until power-cycled. Probe gently.

---

## Applicability

This was tested on a Finnleo SaunaLogic2, but it likely works for other Sauna360-family controllers using the same Tuya product ID (`acl5qrawgmjajabn`). Sauna360 brands include:
- **Finnleo**
- **Tylo**
- **Helo**
- **Amerec**
- **Kastor**

If you have a different Sauna360 sauna with a SaunaLogic2 controller, this device definition should work. If your sauna uses a different Tuya product ID, the DP mapping may still be the same — just add your product ID to the `products` list in the YAML.

---

## The Full Story

Read the complete reverse engineering journey in [docs/journey.md](docs/journey.md) — including the part where we found the sauna on our first network scan, dismissed it as a smart plug, and then spent hours looking for it elsewhere.

---

## Research

- [APK Decompilation Findings](docs/research/apk_decompilation_findings.md) — How we discovered SaunaLogic is Tuya
- [Device Specification](docs/research/bjorn_device_spec.md) — Complete DP mapping with test results
- [Network Discovery](docs/research/network_scan_and_tuya_discovery.md) — How to find your sauna on the network
- [Huum UKU Reverse Engineering](docs/research/huum_uku_reverse_engineering.md) — The reference that inspired this project
- [Huum HA Integration Analysis](docs/research/huum_ha_integration_analysis.md) — Lessons learned from the official Huum integration
- [Sauna RE Landscape](docs/research/sauna_re_landscape.md) — Every sauna HA integration ever built
- [Original Reverse Engineering Plan](reverse_engineering_guide.md) — The plan before we discovered it was Tuya

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing to this project.

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).

---

## Acknowledgments

- [Kaur Palang](https://kaurpalang.com/posts/invading-the-sauna/) for the Huum UKU reverse engineering that showed this was possible
- [tuya_local](https://github.com/make-all/tuya_local) for the HACS integration that makes this work with zero custom code
- [tinytuya](https://github.com/jasonacox/tinytuya) for the device discovery and Tuya protocol tools
