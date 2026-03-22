<!--
Copyright 2026 Chris Keeser
SPDX-License-Identifier: Apache-2.0
-->
# The Finnleo SaunaLogic2 Reverse Engineering Journey

*How a sauna controller turned out to be a Tuya device in a Finnish costume.*

---

## Chapter 1: Research

**Date:** 2026-03-21

Before writing a single line of code, I went looking for people who'd already done the hard work.

### Prior Art

The closest parallel is Kaur Palang's reverse engineering of the Huum UKU WiFi sauna controller, documented in ["Invading the Huum Uku Wifi Controller"](https://kaurpalang.com/posts/invading-the-sauna/). Kaur set up his laptop as a WiFi hotspot, connected the Huum controller, fired up Wireshark, and discovered the entire protocol was unencrypted raw TCP. No TLS. No authentication. Just binary messages flying across the network in plaintext. He spent 3 hours looking for ways to decrypt TLS traffic that didn't exist - the quintessential reverse engineering experience of assuming the target is smarter than it actually is.

He found 5 binary message types, single-byte temperature encoding, and little-endian Unix timestamps. He built a replacement server in Bun/TypeScript, put it on GitHub with 2 commits, and then hit the classic wall: *"But maaan do I not feel like doing it..."* The interesting part was done. The boring production-ready part won by default.

Meanwhile, the official Huum HA integration took a completely different route. Frank Wickstrom built [pyhuum](https://github.com/frwickst/pyhuum), a Python library that talks to Huum's cloud REST API. Simple HTTPS with Basic Auth. Four endpoints: status, start, stop, light. Merged into HA core in 2024.2.

Two approaches to the same problem - one hacker, one polite. The community chose the polite route.

### The RS485 Lead

While surveying every sauna integration I could find, I stumbled onto [esphome-sauna360](https://github.com/tesu84/esphome-sauna360), which explicitly lists Finnleo as a supported brand. This ESPHome project targets the RS485 serial bus on the OLEA 103 adapter board, the same board used across Sauna360's brand family (Finnleo, Tylo, Helo, Kastor, Amerec). If the SaunaLogic2 uses this board internally, the protocol is already documented.

### Lessons from Huum's Mistakes

The Huum HA integration taught me what not to do:
1. The status endpoint had side effects - opening HA would cancel sauna sessions started through the Huum app
2. Fahrenheit was an afterthought - temperature validation was hardcoded to Celsius ranges
3. The API returns garbage sometimes - zero for min/max temperature, causing "must be between 0 and 0" errors
4. No distinction between "heating" and "at temperature" - `hvac_action` was never implemented

---

## Chapter 2: The Tuya Discovery

**Date:** 2026-03-21 (continued)

### Asking Nicely

Before hacking anything, I drafted a polite email to Igor Peric, the CTO of Sauna360, requesting API documentation. Namechecked their competitors who'd already enabled HA integrations. Offered to sign an NDA. Email sent, clock started, moved on.

### APK Decompilation

I installed jadx, downloaded the SaunaLogic APK (v1.1.0), and decompiled it. 33,772 classes. Obfuscated package names like `OooO00o` and `ddbbddkk`.

Then I found the package names that mattered:

`com.thingclips.smart.home.sdk.ThingHomeSdk`

ThingClips. That's Tuya.

The SaunaLogic app isn't a custom application. It's a Tuya OEM white-label app. Sauna360 didn't write a cloud backend or build a custom API. They went to Tuya - the world's largest IoT platform, 500 million+ devices - and said "make us an app."

The `ThingNGConfig.java` file confirmed it:

```java
public static final int appId = 15909;
public static final String region = "International";
public static final String app_scheme = "tyloheloincsaunalogic";
public static final String ap_mode_ssid = "SmartLife";
```

The pairing hotspot SSID is `SmartLife` - the same default used by every Tuya Smart Life device. This is a Tuya device wearing a Finnleo costume.

### Finding the Sauna on the Network

I had 14 unknown IP addresses on the local network. One candidate stood out: an Espressif ESP32 at `<sauna-ip>` with port 6668 open and TTL 254 (embedded firmware). I probed port 6668 with every protocol I could think of - HTTP, MQTT, WebSocket, JSON, binary greetings, RS485-style frames.

Several came back with data:

```
00 00 55 AA ... 33 2E 33 ... 00 00 AA 55
```

Tuya protocol v3.3. Magic bytes `55 AA` at the start, `AA 55` at the end. I dismissed it as a random Tuya smart plug and moved on.

After the APK decompilation revealed the Tuya connection, I went back to the SaunaLogic app and checked the device info. The MAC address matched `ESP_XXXXXX` - the exact device I'd found first, probed, gotten a valid Tuya response from, and dismissed as a smart plug.

The sauna's name in the app was "Bjorn." I'd found it on the first scan.

---

## Chapter 3: Getting Control

**Date:** 2026-03-22

### The OEM Jail

Knowing Bjorn is a Tuya device should have made everything easy. I already had a Tuya developer account, LocalTuya running in HA, and multiple Tuya smart plugs working.

One problem: Tuya OEM apps create separate user accounts. Same email, different password, completely isolated ecosystems. The SaunaLogic account and the Smart Life account are strangers who happen to share a mailbox. I tried QR code scanning, device sharing, API keys from the APK, logging in with SaunaLogic credentials. Dead end after dead end.

### Re-Pairing

I took the slightly nuclear option: remove Bjorn from the SaunaLogic app and re-pair it to Smart Life.

The pairing process: two-press the Bluetooth button on the SL2 controller (beep... beep... display shows "CON1"), device creates a `SmartLife-XXXX` WiFi hotspot. Smart Life's auto-scan couldn't find AP mode devices - I had to dig through the manual pairing flow to find the "AP Mode" option buried behind a "Compatible Mode" link. Multiple attempts. Multiple failures. Then success.

### Data Point Discovery

The Tuya Cloud API immediately revealed Bjorn's registered data points:

| DP | Code | Description |
|---|---|---|
| 1 | `switch` | Power on/off |
| 2 | `temp_set` | Target temperature (25-194 F) |
| 3 | `temp_current` | Current temperature |
| 10 | `countdown_left` | Timer remaining (minutes) |

But the SaunaLogic app controls lighting, Bluetooth audio, and more. Where were those DPs?

I created a custom `tuya_local` device definition with probe sensors for DPs 4-15 and 101-105. After restarting HA, the hidden data points appeared:

| DP | Value | What it is |
|---|---|---|
| 4 | `ONLY_TRAD` | Sauna mode |
| 9 | `1` | Not fully understood |
| 101 | `0` | Light off |
| 103 | `False` | Bluetooth off |
| 105 | `1` | Sauna state (1=idle, 2=running) |

I toggled the light through the app and watched DP 101 change. Off, White, Red, Green, Blue, Yellow, Aqua, Purple, Rainbow - values 0 through 8. A full color controller hiding in an unregistered data point.

### The Crash

After all the probing, Bjorn went silent. The device accepted TCP connections but immediately reset them. The barrage of unknown DP requests during discovery put it into a defensive state.

A power cycle would fix it. But it was freezing outside and the breaker panel is in the cold. Tomorrow.

---

## Chapter 4: Testing

**Date:** 2026-03-22 (the next morning)

I went out in the freezing cold to flip the breaker. Thirty seconds off. Back on. Wait sixty seconds for Bjorn to reconnect.

```
climate.bjorn: off
current_temperature: 51 F
temperature: 194 F
select.bjorn_light: Off
```

Back online. No grudges held.

### Live Testing

With the owner standing at the sauna and me at the keyboard, I ran through every command.

**Light control** - set White from HA, confirmed visually. Set Red, confirmed. Set Rainbow, watched the colors cycle. Set Off. Every color works. Write control to an unregistered Tuya DP, working perfectly.

**Heater control** - set target to 100 F, turned on. The relay clicked. The display showed 119 F (the device has a firmware minimum I hadn't accounted for). Timer auto-set to 60 minutes. Turned off from HA. Relay clicked off.

**Two-way communication** - this was the crucial test. Changes made on the physical control panel, not from HA, not from any app. The owner turned on the heater, changed the target to 137 F, toggled the light to red, turned on Bluetooth. Every change appeared in HA within seconds.

**Bluetooth write** - set Bluetooth on from HA, confirmed on the sauna display. Set off, confirmed. DP 103 is writable in both directions.

**Timer write** - I tried writing custom durations (30, 45 minutes) to DP 10. It appeared to work the first time, but that turned out to be coincidental timing with the panel's own timer setting. On proper retesting, the device silently ignores timer writes. DP 10 is read-only - the timer duration is configured on the physical panel.

**Delay start** - set a 145-minute delay from the panel. DP 9 changed from 1 to 0. The delay countdown itself (145... 144... 143...) showed on the sauna display but didn't appear in any DP. The delay countdown lives in the firmware, unreachable via Tuya.

### Results

| Feature | Status |
|---------|--------|
| Heater on/off | Working (bidirectional) |
| Target temperature | Working (25-194 F) |
| Current temperature | Working (real-time) |
| Light color (9 modes) | Working (writable) |
| Bluetooth toggle | Working (writable) |
| Session timer | Read-only (countdown visible, writes ignored) |
| Sauna mode | Read-only ("ONLY_TRAD") |
| Run state | Read-only (1=idle, 2=running) |
| DP 9 | Read-only, not fully understood |
| Delay countdown | Not exposed via Tuya DP |
| Two-way sync | Working (physical panel changes appear in HA in real-time) |

### What This Means

This is, as far as I know, the first successful Home Assistant integration for a Finnleo SaunaLogic2 sauna controller. No custom integration code. No reverse-engineered binary protocol. No cloud API hacking. Just:

1. A decompiled APK that revealed the Tuya OEM platform
2. A re-pairing to Smart Life for local key access
3. A 40-line YAML device definition for `tuya_local`
4. A trip out into the cold to flip the breaker

Total custom code written: zero lines.
