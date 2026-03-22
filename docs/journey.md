# The Finnleo SaunaLogic2 Reverse Engineering Journey

*A chronicle of building a Home Assistant integration for a sauna controller that doesn't want to be integrated.*

---

## Prologue

There's a sauna in the house. A Finnleo sauna, controlled by a SaunaLogic2 controller. It connects to WiFi. It has an app. It works with Google Home and Alexa. It does everything a modern smart device should do.

Except talk to Home Assistant.

There is no official integration. There is no community integration. There is no HACS plugin. There isn't even a forum post where someone says "I tried and failed." The SaunaLogic2 sits in its little cloud bubble, surrounded by Sauna360's servers, perfectly happy to never expose a single API endpoint to the likes of us.

We're going to change that.

---

## Chapter 1: Standing on the Shoulders of Sauna Giants

**Date:** 2026-03-21

Before writing a single line of code, we did what any responsible reverse engineer does: we went looking for people who already did the hard work.

### The Huum UKU Story

The closest parallel to what we're attempting is Kaur Palang's reverse engineering of the Huum UKU WiFi sauna controller, documented in his blog post ["Invading the Huum Uku Wifi Controller"](https://kaurpalang.com/posts/invading-the-sauna/).

The short version: Kaur set up his laptop as a WiFi hotspot, connected the Huum controller to it, fired up Wireshark, and discovered something that made him both delighted and horrified — **the entire protocol was unencrypted raw TCP**. No TLS. No authentication. No nothing. Just binary messages flying across the network in plaintext.

He spent 3 hours looking for ways to decrypt TLS traffic that didn't exist. We love this detail. This is the reverse engineering experience in its purest form: assuming the target is smarter than it actually is.

What he found:
- **5 binary message types** controlling the entire heater (greeting, ping frequency, heater control, state update, status ping)
- **Single-byte temperature encoding** (0x5A = 90°C, just hex-to-decimal)
- **Little-endian Unix timestamps** for heating schedules
- **DNS-based redirection** to route controller traffic to a local server

He built a replacement server in Bun/TypeScript, put it on GitHub with 2 commits, and then hit the classic developer wall: *"But maaan do I not feel like doing it..."* The interesting reverse engineering was done. The boring "make it production-ready" part won by default.

Meanwhile, the **official Huum HA integration** went a completely different route. Frank Wickstrom built [pyhuum](https://github.com/frwickst/pyhuum), a Python library that talks to Huum's cloud REST API (`https://sauna.huum.eu/action/home/`). Simple HTTPS with Basic Auth. Four endpoints: status, start, stop, light. It was merged into HA core in 2024.2 and currently has about 170 active installations.

**The punchline:** Two completely different approaches to the same problem:
- Kaur went full hacker mode, intercepted raw TCP, built a local server replacement
- Frank went the polite route, used the official cloud API, built a proper HA integration

Both work. The community chose the polite route for the official integration.

### The Bombshell Discovery

While surveying the landscape of every sauna integration we could find, we stumbled onto something that made us sit up straight.

**[esphome-sauna360](https://github.com/tesu84/esphome-sauna360) explicitly lists Finnleo as a supported brand.**

This ESPHome project targets the RS485 serial bus on the OLEA 103 adapter board — the same board used across Sauna360's entire family of brands (Finnleo, Tylo, Helo, Kastor, Amerec). If the SaunaLogic2 uses this board internally, the protocol is already documented. RS485 at 19200 baud, even parity, with a well-defined frame format.

This means we potentially have **two attack vectors**:
1. **Cloud API interception** — mitmproxy the SaunaLogic app, document the HTTPS API
2. **RS485 bus tapping** — Open the controller, find the OLEA 103 board, tap the bus with a $20 ESP32 + MAX485 setup

And a third option that requires zero hacking:
3. **Just ask Sauna360 nicely** — Saunum got their integration into HA core by providing Modbus documentation to a developer. Sauna360 might do the same.

### The Landscape

We cataloged every sauna reverse engineering effort and HA integration we could find:

| Sauna | Protocol | Encrypted? | Local? | HA Integration |
|-------|----------|-----------|--------|----------------|
| Huum UKU (local) | Raw TCP | No | Yes (DNS redirect) | Community server |
| Huum (cloud) | HTTPS REST | Yes | No | Official (HA 2024.2) |
| Sauna360 family (RS485) | RS485 serial | N/A | Yes | ESPHome component |
| Harvia Xenio | MQTT | Yes | No | HACS integration |
| Saunum Leil | Modbus TCP | No | Yes | Official (HA 2025.12) |
| Effe ECC | Raw TCP | Unknown | Yes | Community integration |
| **Finnleo SaunaLogic2** | **Unknown** | **Likely yes** | **Unknown** | **This project** |

### Lessons from Huum's Mistakes

The Huum HA integration has taught us what NOT to do:
1. **The status endpoint had side effects** — Opening HA would cancel sauna sessions started through the Huum app. Status polling should be read-only. Always.
2. **Fahrenheit was an afterthought** — Temperature validation was hardcoded to Celsius ranges. Setting 120°F was rejected. Still broken as of this writing.
3. **The API returns garbage sometimes** — Zero for min/max temperature, causing "must be between 0 and 0" errors. Always have fallback defaults.
4. **No distinction between "heating" and "at temperature"** — The `hvac_action` attribute was never implemented despite the API having distinct status codes.

We will not make these mistakes.

---

## What's Next

The research phase is done. Here's the plan:

1. **Port scan the SaunaLogic2** — See if it exposes any local services (the quick win)
2. **Check DNS queries** — What servers does the SL2 talk to?
3. **Set up mitmproxy** — Intercept the SaunaLogic app's HTTPS traffic
4. **Inspect the physical controller** — Look for an OLEA 103 board and RS485 bus
5. **Try asking Sauna360** — The polite approach that might save us months of work

One of these will crack it open. We'll document every step, every dead end, and every moment we spend 3 hours looking for TLS that doesn't exist.

Let's go.

---

## Chapter 2: The Polite Approach and the Lucky Break

**Date:** 2026-03-21 (continued)

### Asking Nicely

Before we started hacking anything, we drafted a polite email to Igor Peric, the CTO of Sauna360, requesting API documentation. We namechecked their competitors (Huum, Saunum) who had already enabled HA integrations. We offered to sign an NDA. We were professional and charming.

We also discovered that someone else had tried this before — a user on the HA forums emailed Tylo support in Sweden and got exactly zero response. But they had gone through the support channel. We went to the CTO directly. Different game.

Email sent. Clock started. We moved on.

### The Network Scan (A Comedy of Errors)

We had 14 unknown IP addresses on the network. One of them, surely, was the sauna. We ran port scans. We probed TCP connections. We did MAC address vendor lookups.

Our initial top candidate: **<sauna-ip>** (`ESP_XXXXXX`). Espressif chip. Port 6668 open. TTL 254 (embedded firmware). Everything pointed to "this is the sauna."

So we probed port 6668 with every protocol we could think of: HTTP, MQTT, WebSocket, JSON, binary greetings, even RS485-style frames. Most got no response. But a few came back with data:

```
00 00 55 AA ... 33 2E 33 ... 00 00 AA 55
```

That's the **Tuya protocol**. Magic bytes `55 AA` at the start, `AA 55` at the end, protocol version "3.3" in the middle. <sauna-ip> isn't the sauna — it's some random Tuya smart plug or switch.

We also identified the other 13 devices: three Meross smart plugs, a Blink camera, a Brother printer, a Resideo cold plunge gateway, a ParamTech water level meter, some phones, an Amazon Echo, and a Particle IoT device.

**The sauna wasn't in the list.** It's either not connected, has a different IP we already identified as something else, or exposes zero network services.

### The APK Decompilation (The Big One)

While the network scan was running, we installed Java and jadx, downloaded the SaunaLogic APK (v1.0.1, v1.0.2, and v1.1.0), and decompiled the latest version.

33,772 classes. Obfuscated package names like `OooO00o`, `ddbbddkk`, and `bvjgk374138bb27`. A jungle of code.

We searched for API endpoints. We searched for "sauna." We searched for "heater" and "temperature."

And then we found the package names.

`com.thingclips.smart.home.sdk.ThingHomeSdk`

ThingClips. **That's Tuya.**

The SaunaLogic app isn't a custom application. It's a **Tuya OEM white-label app**. Sauna360 didn't write a cloud backend. They didn't build a custom API. They went to Tuya — the world's largest IoT platform (500 million+ devices) — and said "make us an app."

The entire cloud infrastructure, the device communication protocol, the Google Home integration, the Alexa support — it's all Tuya. The `ThingNGConfig.java` file had it all laid bare:

```java
public static final int appId = 15909;
public static final String region = "International";
public static final String app_scheme = "tyloheloincsaunalogic";
public static final String ap_mode_ssid = "SmartLife";  // The default Tuya hotspot name!
```

`SmartLife`. The pairing hotspot SSID is `SmartLife` — the same name used by the default Tuya Smart Life app. This is a Tuya device wearing a Finnleo costume.

### Why This Changes Everything

Remember how we were planning to set up mitmproxy, bypass certificate pinning, intercept HTTPS traffic, reverse-engineer a proprietary binary protocol, and build everything from scratch?

We might not need to do any of that.

Tuya devices already have **two mature Home Assistant integrations**:
1. **Official Tuya integration** — Cloud-based, supports thousands of Tuya device types
2. **LocalTuya** (HACS) — Local control via the Tuya protocol on port 6668

The protocol we probed on the network? That was Tuya protocol v3.3. It's well-documented. It's been reverse-engineered years ago. There are multiple open-source implementations.

The only thing we need to know is **what data points (DPs) the SaunaLogic2 exposes**. In Tuya's system, every device capability is a numbered "data point" — DP 1 might be power on/off, DP 2 might be target temperature, DP 3 might be timer, etc. Once we know the DPs, we can control the sauna through the existing Tuya infrastructure.

### What's Left to Do

1. **Create a Tuya IoT developer account** and link the SaunaLogic app account to discover the device's data points
2. **Try the official Tuya HA integration** — it might already work out of the box
3. **Try LocalTuya** for local control
4. **If the existing integrations don't handle sauna-specific features well**, build a custom integration that maps sauna DPs to proper HA climate/switch/sensor entities

The hardest part of reverse engineering is figuring out what you're looking at. We just figured out we're looking at Tuya. And Tuya has already been reverse-engineered by an army of smart home enthusiasts over the past decade.

Sometimes the best hack is realizing you don't need to hack anything at all.

---

## Chapter 3: Finding Björn

**Date:** 2026-03-22

### The Network Hunt

We had 14 unknown IP addresses on the local network. One of them was the sauna. We scanned ports, probed protocols, looked up MAC vendors.

Our first candidate: **<sauna-ip>** — an Espressif ESP32 with port 6668 open. We probed it with 10 different protocol handshakes: HTTP, MQTT, WebSocket, JSON, binary greetings, TLS, even RS485-style frames. Several came back with data:

```
00 00 55 AA ... 33 2E 33 ... 00 00 AA 55
```

Tuya protocol v3.3. Magic bytes `55 AA` and `AA 55`. Clear as day.

"That's not the sauna," we said confidently. "That's just some random Tuya smart plug."

We moved on. We identified every other device — Meross plugs, Blink cameras, Brother printers, a cold plunge gateway, a ParamTech water level meter. We were thorough. We were professional. We were *wrong*.

### The APK Decompilation

Meanwhile, we decompiled the SaunaLogic Android APK. 33,772 classes. Obfuscated package names like `OooO00o` and `ddbbddkk`. We searched for "sauna," "heater," "temperature," API endpoints.

And found `com.thingclips.smart.home.sdk.ThingHomeSdk`.

ThingClips. That's **Tuya**.

The entire SaunaLogic app is a Tuya OEM white-label app (appId 15909). Sauna360 didn't build anything — they went to Tuya's OEM program and said "make us a sauna app."

Which meant... that device at <sauna-ip> responding with Tuya protocol... might actually be...

We went back to the SaunaLogic app. Device info. MAC address: `xx:xx:xx:xx:xx:xx`.

That's `ESP_XXXXXX`. That's `<sauna-ip>`. That's the device we found first, probed, got a valid Tuya response from, and then **dismissed as a random smart plug**.

The sauna's name in the app? **Björn**.

We found Björn on the first scan and didn't even know it.

### The OEM Jail

Knowing Björn is a Tuya device should have made everything easy. The user already had a Tuya developer account, LocalTuya running in HA, and multiple Tuya smart plugs working perfectly.

One problem: Tuya OEM apps create **separate user accounts**. Same email, different password, completely isolated ecosystems. The SaunaLogic account and the Smart Life account are strangers who happen to share a mailbox.

We tried everything to bridge the gap:
- **Scan QR code with SaunaLogic app** — "please use the designated APP to scan the code to log in"
- **Share device to Smart Life** — share link hardcoded to SaunaLogic app only
- **Tuya Cloud API with APK keys** — SDK keys ≠ Cloud API keys
- **Log into Smart Life with SaunaLogic credentials** — wrong password (separate accounts)

Dead end after dead end.

### The Re-Pairing

We took the slightly nuclear option: remove Björn from the SaunaLogic app and re-pair it to Smart Life.

The pairing process: two-press the Bluetooth button on the SL2 controller (beep... beep... display shows "CON1"), device creates a `SmartLife-XXXX` WiFi hotspot. Connect phone to hotspot. Smart Life app pairs the device.

Except Smart Life's auto-scan couldn't find AP mode devices. We had to dig through the manual pairing flow to find the "AP Mode" option buried behind a "Compatible Mode" link. Multiple attempts. Multiple failures.

Then, success. Björn appeared in Smart Life.

### The Data Points

The Tuya Cloud API immediately revealed Björn's registered data points:

| DP | Code | Description |
|---|---|---|
| 1 | `switch` | Power on/off |
| 2 | `temp_set` | Target temperature (25-194°F) |
| 3 | `temp_current` | Current temperature |
| 10 | `countdown_left` | Timer remaining (minutes) |

But we wanted more. The SaunaLogic app controls lighting, Bluetooth audio, and delay start. Where were those DPs?

We created a custom device definition for the `tuya_local` integration with probe sensors for DPs 4-15 and 101-105. Restarted HA. And found **hidden data points** the cloud API didn't advertise:

| DP | Value | Discovery |
|---|---|---|
| 4 | `ONLY_TRAD` | Sauna mode |
| 9 | `1` | Unknown (always 1) |
| 101 | `0` | Light off |
| 103 | `False` | Bluetooth off |
| 105 | `1` | Sauna state (1=idle, 2=running) |

Then we toggled the light through the app and watched DP 101 change. Off, White, Red, Green, Blue, Yellow, Aqua, Purple, Rainbow — values 0 through 8. A full RGBW light controller hiding in an unregistered data point.

### The Complete Björn Specification

After two hours of probing, toggling, and cross-referencing, we have the complete map:

**Controllable:**
- DP 1: Power on/off (Boolean)
- DP 2: Target temperature, 25-194°F (Integer)
- DP 101: Light mode — Off/White/Red/Green/Blue/Yellow/Aqua/Purple/Rainbow (Integer 0-8)
- DP 103: Bluetooth audio on/off (Boolean)

**Read-only:**
- DP 3: Current temperature (Integer, °F)
- DP 10: Timer countdown remaining, 0-1440 minutes (Integer)
- DP 4: Sauna mode, "ONLY_TRAD" (String)
- DP 105: Sauna state — 1=idle, 2=running (Integer)

**Still unknown:**
- DP 9: Always 1
- DP 11: Always 0

### The Temporary Setback

After all the probing, Björn went silent. The device accepts TCP connections but immediately resets them. We think the barrage of unknown DP requests during discovery put the device into a defensive state.

All the other Tuya devices on the network work fine. It's just Björn being stubborn — appropriately Nordic behavior for a sauna named after a bear.

A power cycle will fix it. But it's freezing outside and the breaker panel is in the cold. Tomorrow.

### What We Built

A custom `tuya_local` device definition (`tylohelo_sl2_sauna.yaml`) that maps the SaunaLogic2's data points to HA entities:
- **Climate entity** — temperature control with correct °F units
- **Select entity** — light color mode dropdown
- **Sensor** — timer countdown
- **Diagnostic sensors** — sauna mode, state, Bluetooth status

When Björn comes back online after a power cycle, this definition will give full local, cloud-free control of a Finnleo sauna in Home Assistant. No custom integration needed. No reverse engineering of a proprietary protocol. Just a Tuya device wearing a fancy Finnish costume.

### The Irony

We started this project expecting months of work: mitmproxy, SSL pinning bypass, binary protocol analysis, custom cloud API reverse engineering. We studied the Huum UKU effort (raw TCP, 5 message types, no encryption). We cataloged every sauna integration ever built.

Then we decompiled the app and found it was Tuya all along.

The entire "reverse engineering" effort turned into: decompile APK, discover it's Tuya, pair to Smart Life, read DPs from the cloud API, probe for hidden DPs, write a YAML file.

Total custom code written: **zero lines**.

Sometimes the best reverse engineering is discovering there's nothing to reverse-engineer.

---

## Chapter 4: Björn Lives

**Date:** 2026-03-22 (the next morning)

### The Power Cycle

The previous night ended with Björn in a sulk — accepting TCP connections but refusing to talk. We'd hammered it with too many unknown DP requests during discovery and it went into a defensive state.

A trip out into the freezing cold to flip the breaker. Thirty seconds off. Back on. Wait sixty seconds for Björn to reconnect to WiFi and re-establish the Tuya local protocol session.

```
climate.bjorn: off
current_temperature: 51°F
temperature: 194°F
select.bjorn_light: Off
```

Björn was back. Every entity reporting. No grudges held.

### The Test Suite

With the owner standing at the sauna and Claude at the keyboard, we ran through every command:

**Light control** — set White from HA, confirmed visually. Set Red, confirmed. Set Rainbow, watched the colors cycle. Set Off. Every color works. Write control to an unregistered Tuya DP, working flawlessly.

**Heater control** — set target to 100°F, turned on. The relay clicked. Warmth from the heater. The display showed 119°F (the device has a firmware minimum we hadn't accounted for). Timer auto-set to 60 minutes. Turned off from HA. Relay clicked off. The sauna responds to Home Assistant.

**Two-way communication** — this was the crucial test. Changes made on the physical control panel, not from HA, not from any app. Just pressing buttons on the sauna.

The owner turned on the heater, changed the target to 137°F, toggled the light to red, turned on Bluetooth. Every change appeared in HA within seconds. Real-time, bidirectional, local communication.

Then the delay test. Set a 145-minute delay from the panel. DP 9 flipped from 1 to 0 — a flag we'd previously marked as "unknown (always 1)." The delay countdown itself (145... 144... 143...) showed on the sauna display but didn't appear in any DP. The delay countdown lives in the firmware, unreachable via Tuya. A minor limitation we can live with.

### The Final Score

| Feature | Status |
|---------|--------|
| Heater on/off | Working (HA → sauna, sauna → HA) |
| Target temperature | Working (25-194°F) |
| Current temperature | Working (real-time) |
| Session timer | Working (countdown in minutes) |
| Light on/off | Working |
| Light colors (9 modes) | Working (Off/White/Red/Green/Blue/Yellow/Aqua/Purple/Rainbow) |
| Bluetooth toggle | Read-only (detected, not yet tested as writable) |
| Sauna mode | Read-only ("ONLY_TRAD") |
| Run state | Read-only (1=idle, 2=running) |
| Delay flag | Read-only (1=normal, 0=delay set) |
| Delay countdown | Not exposed via Tuya DP |
| Two-way sync | Working (physical panel → HA in real-time) |

### What This Means

This is, as far as we know, the **first successful Home Assistant integration for a Finnleo SaunaLogic2 sauna controller**. No custom integration code. No reverse-engineered binary protocol. No cloud API hacking. Just:

1. A decompiled APK that revealed the Tuya OEM platform
2. A re-pairing to Smart Life for local key access
3. A 40-line YAML device definition for `tuya_local`
4. A lot of trips out into the cold

The sauna is now a first-class citizen in Home Assistant. Automations, dashboards, voice control — all possible. "Hey Google, preheat the sauna" is no longer a dream.

Björn lives.
