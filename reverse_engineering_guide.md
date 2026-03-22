<!--
Copyright 2026 Chris Keeser
SPDX-License-Identifier: Apache-2.0
-->
# Finnleo SaunaLogic2 — Reverse Engineering Guide

> **Note:** This was the original plan before we discovered the SaunaLogic2 is a Tuya OEM device. None of the approaches below were needed — the actual solution required zero custom code. See the [README](README.md) for the real solution. This document is preserved as historical context.

## Original Goal
Build a Home Assistant custom integration for the Finnleo SaunaLogic2 sauna controller by reverse-engineering its cloud API.

---

## Background

### Product
- **Sauna**: Finnleo (brand of Sauna360, formerly TyloHelo, acquired by Masco Corporation in 2023)
- **Controller**: SaunaLogic2 (SL2) — WiFi-connected sauna controller
- **App**: SaunaLogic (iOS: `com.saunalogic`, [App Store](https://apps.apple.com/us/app/saunalogic/id1486728700))
- **Manufacturer**: Sauna360 Inc. (also owns Tylo, Helo, Kastor, Amerec brands)

### Architecture
The SaunaLogic2 uses a **cloud-relay architecture**:
1. During initial setup, the SL2 creates a temporary WiFi hotspot for pairing
2. The phone connects directly to the SL2 hotspot and configures it with the home WiFi credentials
3. After pairing, the SL2 connects to the home WiFi and communicates with Sauna360's cloud servers
4. **The phone app communicates with the SL2 via the internet, NOT directly on the local network**
5. The SL2 requires 2.4 GHz WiFi (does not support 5 GHz)

From the official pairing instructions:
> "After the SL2 is connected to the Wi-Fi network, the phone will not connect directly to the control again. The phone/tablet will communicate with the SL2 control via the internet."

### Smart Home Integration
SaunaLogic2 natively supports:
- **Google Home** — voice control via Google Assistant
- **Amazon Alexa** — voice control
- **Apple Siri** — via Siri Shortcuts

This means a cloud API exists that supports these platforms. The Google Home and Alexa integrations require the SaunaLogic service to implement standard smart home APIs (Google Smart Home Actions, Alexa Smart Home Skill), which typically expose device capabilities in a structured way.

### What the App Controls
- Power on/off
- Target temperature
- Timer (up to 60 minutes, built-in safety limit)
- Sauna light
- Delay start (schedule sauna to turn on later)
- Multiple sauna support (if you have more than one)

---

## Current HA Integration Landscape

### No Direct Integration Exists
- No official HA integration for Finnleo, SaunaLogic, TyloHelo, or Sauna360
- No HACS custom integration
- No community member has published a reverse-engineering effort for SaunaLogic

### Related Work

#### Huum UKU Reverse Engineering (closest reference)
The [Huum UKU WiFi sauna controller](https://kaurpalang.com/posts/invading-the-sauna/) was successfully reverse-engineered by Kaur Palang. Key findings from that effort:
- The Huum UKU used **unencrypted raw TCP** to communicate with its cloud server
- Interception was straightforward using Wireshark
- The protocol was simple enough to replicate in a custom HA integration
- This resulted in the official `huum` HA integration (added in HA 2024.2)
- **Read this post thoroughly** — it's the best reference for the approach and methodology

#### Harvia MyHarvia (competitor, different API)
- [ha-harvia-xenio-wifi](https://github.com/RubenHarms/ha-harvia-xenio-wifi) — HACS integration for Harvia saunas
- Uses the MyHarvia cloud API
- Harvia is a competitor (separate Finnish company), NOT compatible with Finnleo
- But the codebase structure is a useful reference for building an HA sauna integration

#### Tylo Elite RS485 (same parent company, hardware approach)
- [esphome-tylo](https://github.com/f-io/esphome-tylo) — ESPHome integration for Tylo Helo Elite controllers
- Uses RS485 serial bus communication directly with the controller board
- Tylo is owned by Sauna360 (same as Finnleo), so the hardware may share some design DNA
- This is a hardware modification approach, not a cloud API approach
- The SaunaLogic2 may or may not have an RS485 bus internally

#### HA Community Threads
- [Tylo Helo Sauna Controller Elite integration](https://community.home-assistant.io/t/tylo-helo-sauna-controller-elite-integration/649909) — RS485-based approach for Tylo Elite
- [Cloud-free sauna heater control](https://community.home-assistant.io/t/cloud-free-sauna-heater-control/962070) — User built custom ESP32 solution to avoid SaunaLogic2's cloud dependency

---

## Reverse Engineering Plan

### Phase 1: Passive Traffic Analysis

**Goal:** Capture and analyze network traffic between the SaunaLogic app and the cloud servers to understand the API.

#### Option A: Android App with mitmproxy (Recommended)

1. **Install mitmproxy** on a computer on the same network
   ```bash
   pip install mitmproxy
   mitmweb --listen-port 8080
   ```

2. **Configure Android phone** to use mitmproxy as HTTP proxy:
   - WiFi settings → proxy → manual → set to computer's IP:8080
   - Install mitmproxy's CA certificate on the phone (visit `mitm.it` through the proxy)

3. **Open the SaunaLogic app** and perform all available actions:
   - Login
   - View sauna status
   - Turn on/off
   - Set temperature
   - Set timer
   - Delay start
   - Toggle light

4. **Capture all requests/responses** — look for:
   - API base URL (likely `*.sauna360.com` or similar)
   - Authentication method (OAuth2, API key, session token, etc.)
   - Request/response format (JSON, XML, binary)
   - WebSocket connections (for real-time status updates)
   - Device identifiers (serial number, MAC, registration ID)

5. **Potential blocker: Certificate pinning**
   - Modern apps may pin the server's TLS certificate, rejecting mitmproxy's CA
   - If pinned: use [Frida](https://frida.re/) with [objection](https://github.com/sensepost/objection) to bypass pinning on a rooted Android device
   - Alternative: use an older version of the app (APK from APKMirror) which may not have pinning

#### Option B: Network-Level Capture with Wireshark

1. **Mirror the SL2's network traffic** at the router level (if your router supports port mirroring) or use an ARP spoofing tool like `arpspoof` to intercept the SL2's traffic
2. **Capture with Wireshark** — filter by the SL2's IP address
3. Look for:
   - DNS queries (reveals the cloud server hostname)
   - Connection protocol (HTTPS, MQTT, raw TCP, WebSocket)
   - Connection frequency (does the SL2 maintain a persistent connection or poll?)
   - If unencrypted (like the Huum UKU was): protocol is directly visible
   - If TLS-encrypted: you'll only see the server hostname (via SNI) and connection patterns

#### Option C: DNS + Cloud Endpoint Discovery

Even without full traffic capture, you can learn a lot:
1. **Check DNS queries** from the SL2 by examining your router's DNS logs or running `tcpdump` on the network
2. **Identify the cloud server hostname(s)** the SL2 connects to
3. **Probe the cloud endpoints** with `curl` to see if there's a public API
4. **Check the Google Home / Alexa integration endpoints** — these are often documented or discoverable:
   - Google: The SaunaLogic Google Home Action has a fulfillment URL
   - Alexa: The SaunaLogic Alexa Skill has a Lambda endpoint

### Phase 2: API Documentation

Once traffic is captured, document:

1. **Authentication flow**
   - How does the app log in? (email/password → token?)
   - Token format (JWT, opaque, session cookie?)
   - Token refresh mechanism
   - Does the SL2 authenticate independently to the cloud?

2. **Device discovery**
   - How does the app know which saunas are linked to the account?
   - Device identifiers (serial number, MAC, cloud ID?)

3. **Command API**
   - Turn on/off
   - Set temperature (min/max, step)
   - Set timer duration
   - Delay start
   - Light control
   - Request format and response format

4. **Status polling**
   - How does the app get current sauna status?
   - Polling interval vs WebSocket/push
   - Available status fields (current temp, target temp, time remaining, heater state, light state)

5. **Rate limits**
   - Any throttling or rate limiting on the API?
   - How frequently can commands be sent?

### Phase 3: Local API Discovery (Bonus)

Even though the docs say the phone communicates via the internet, it's worth checking if the SL2 exposes any local services:

1. **nmap the SL2's IP address**
   ```bash
   nmap -sV -p- <sl2_ip_address>
   ```
   Look for open ports (HTTP, MQTT, mDNS, etc.)

2. **Check mDNS/Bonjour**
   ```bash
   avahi-browse -a   # Linux
   dns-sd -B _tcp    # macOS
   ```
   Some IoT devices advertise local services via mDNS

3. **Check for UPnP/SSDP**
   ```bash
   gssdp-discover
   ```

4. If any local API exists, this would enable **cloud-free local control** — the ideal outcome

### Phase 4: Build the HA Integration

#### Integration Structure
```
custom_components/finnleo/
├── __init__.py          # Integration setup
├── manifest.json        # Integration metadata
├── config_flow.py       # UI configuration
├── climate.py           # Climate platform (temperature control)
├── switch.py            # Light control, power on/off
├── sensor.py            # Status sensors (current temp, time remaining)
├── coordinator.py       # Data update coordinator
├── api.py               # SaunaLogic API client
└── const.py             # Constants
```

#### HA Platform Mapping
| Sauna Feature | HA Platform | Entity Type |
|---|---|---|
| Power on/off | `climate` | HVAC mode (heat/off) |
| Target temperature | `climate` | Temperature setpoint |
| Current temperature | `climate` | Current temperature attribute |
| Timer | `number` or `climate` | Preset or custom attribute |
| Light | `light` or `switch` | On/off |
| Delay start | `number` or `datetime` | Minutes or scheduled time |
| Heater status | `binary_sensor` | Is heating |

#### Reference Codebases
- [Huum integration (official)](https://github.com/home-assistant/core/tree/dev/homeassistant/components/huum) — simplest sauna integration, good starting template
- [Saunum integration (official)](https://github.com/home-assistant/core/tree/dev/homeassistant/components/saunum) — newer, more features
- [ha-harvia-xenio-wifi (HACS)](https://github.com/RubenHarms/ha-harvia-xenio-wifi) — cloud API approach for a competing sauna brand

---

## Tools Needed

| Tool | Purpose | Install |
|---|---|---|
| **mitmproxy** | HTTP/HTTPS traffic interception | `pip install mitmproxy` |
| **Wireshark** | Network packet capture | [wireshark.org](https://www.wireshark.org/) |
| **nmap** | Port scanning the SL2 | `apt install nmap` or [nmap.org](https://nmap.org/) |
| **Frida** | SSL pinning bypass (if needed) | `pip install frida-tools` |
| **Android emulator or rooted phone** | For certificate installation | Android Studio or physical device |
| **curl / httpie** | API testing | `pip install httpie` |

---

## Quick Wins Before Full Reverse Engineering

### 1. DNS Reconnaissance
Check what servers the SL2 talks to — can be done from your router's DNS logs or by monitoring network traffic briefly:
```bash
# On a machine on the same network, capture DNS queries from the SL2's IP
sudo tcpdump -i any -nn port 53 and host <sl2_ip>
```

### 2. Port Scan the SL2
See if there's any local API exposed:
```bash
nmap -sV -p- <sl2_ip>
```

### 3. Check the App's Network Calls
Before setting up mitmproxy, check if the app makes plain HTTP calls:
- On Android: enable Developer Options → "Show Network Calls" in developer settings
- Use Android Studio's Network Profiler with a debug build

### 4. Google Home Integration Clues
Link the sauna to Google Home (even temporarily) and observe:
- What device type Google sees it as (thermostat, switch, etc.)
- What controls are exposed (on/off, temperature, modes)
- This reveals what the cloud API exposes

---

## Resources

### Direct References
- [SaunaLogic2 Product Page](https://www.finnleo.com/saunalogic2)
- [SaunaLogic2 Pairing Instructions (PDF)](https://f.hubspotusercontent30.net/hubfs/17432/docs/Manuals/Heaters_Controls/Controls/72-0135%204211-410%20SL2%20App%20Pairing%20Instructions%20Rev%205%2003-19-2021.pdf)
- [SaunaLogic iOS App](https://apps.apple.com/us/app/saunalogic/id1486728700)
- [Sauna360 (parent company)](https://sauna360.com/about-us)

### Reverse Engineering References
- [Invading the Sauna — Huum UKU Reverse Engineering](https://kaurpalang.com/posts/invading-the-sauna/) — **Read this first.** Best reference for the methodology.
- [mitmproxy Documentation](https://docs.mitmproxy.org/)
- [Frida SSL Pinning Bypass Guide](https://codeshare.frida.re/@pcipolloni/universal-android-ssl-pinning-bypass-with-frida/)
- [Objection — Runtime Mobile Exploration](https://github.com/sensepost/objection)

### HA Integration Development
- [HA Integration Tutorial](https://developers.home-assistant.io/docs/creating_component_index)
- [HA Climate Platform](https://developers.home-assistant.io/docs/core/entity/climate)
- [Huum Integration Source](https://github.com/home-assistant/core/tree/dev/homeassistant/components/huum)
- [Saunum Integration Source](https://github.com/home-assistant/core/tree/dev/homeassistant/components/saunum)
- [ha-harvia-xenio-wifi Source](https://github.com/RubenHarms/ha-harvia-xenio-wifi)

### Community
- [HA Community: Tylo Helo Elite Integration](https://community.home-assistant.io/t/tylo-helo-sauna-controller-elite-integration/649909)
- [HA Community: Cloud-Free Sauna Control](https://community.home-assistant.io/t/cloud-free-sauna-heater-control/962070)
- [esphome-tylo (RS485 for Tylo controllers)](https://github.com/f-io/esphome-tylo)
