# Sauna Reverse Engineering & HA Integration Landscape

A survey of every known sauna reverse engineering effort and Home Assistant integration, with lessons for our Finnleo SaunaLogic2 project.

---

## Direct Competitors & Related Work

### 1. esphome-sauna360 — **THE MOST RELEVANT FIND**

**Repo:** [tesu84/esphome-sauna360](https://github.com/tesu84/esphome-sauna360)
**License:** Apache 2.0
**Status:** Active (75 commits)

**THIS PROJECT EXPLICITLY LISTS FINNLEO AS A SUPPORTED BRAND.**

It targets Sauna360-family controllers (Finnleo, Helo, Tylo, TyloHelo, Amerec, Kastor) via the **RS485 serial bus** on the **OLEA 103 adapter board**.

#### Protocol Details
- **RS485** at 19200 baud, 8 data bits, even parity, 1 stop bit (8E1)
- Connection via 4-wire cable or RJ10 telephone jack on the OLEA 103 board
- Requires 220-ohm termination resistor between A and B lines for PURE panels

#### Frame Format
```
SOF (0x98) | Address (0x40) | Message Type | Code (2 bytes) | Data (0-4 bytes) | CRC (2 bytes) | EOF (0x9C)
```

#### Available Entities
- Heater status (on/off)
- Light status
- Ready status
- Current temperature
- Temperature setpoint
- Bath time remaining
- Humidity level

#### Available Controls
- Power on/off
- Standby mode
- Bath time (1-360 minutes)
- Bath temperature (40-110°C)

#### What This Means for Us
If the SaunaLogic2 uses an OLEA 103 adapter board internally (which is plausible given Finnleo is part of Sauna360), we might be able to:
1. Open the controller enclosure and identify the board
2. Tap into the RS485 bus with an ESP32 + MAX485 transceiver (~$20 in parts)
3. Get **fully local, cloud-free control** using this existing protocol

**This is a hardware approach. It requires physical access to the controller's internals. But it would be the gold standard result — zero cloud dependency.**

---

### 2. esphome-tylo — Same RS485 Protocol

**Repo:** [f-io/esphome-tylo](https://github.com/f-io/esphome-tylo)
**License:** Apache 2.0

Same Sauna360 family, same RS485 protocol. Developed for Tylo Sense Pure, with basic support for Combi and Elite variants.

Key details:
- Message types: `0x06` (heater request), `0x07` (panel command), `0x08` (heater data), `0x09` (panel data/ACK)
- Hardware: ESP32-S3 + MAX485 transceiver, total cost under €20
- Legally justified as observation "between lawfully acquired devices for interoperability purposes"

---

### 3. Harvia MyHarvia — MQTT Cloud API

**Repo:** [RubenHarms/ha-harvia-xenio-wifi](https://github.com/RubenHarms/ha-harvia-xenio-wifi)
**Platform:** HACS custom integration

Harvia is a competing Finnish sauna company (not Sauna360-owned). Their WiFi controller uses **secure MQTT** (port 8883). The HACS integration reverse-engineered the cloud API.

**Relevance:** Different company, incompatible protocol. But the codebase structure is a useful reference for building a cloud-based sauna HA integration.

Also see: [SwiCago/HarviaWiFi](https://github.com/SwiCago/HarviaWiFi) — ESP8266-based approach using Sonoff TH16 + MQTT.

---

### 4. Saunum Leil — Modbus TCP (Manufacturer Cooperated)

**HA Community:** [Saunum Leil Control Unit](https://community.home-assistant.io/t/saunum-leil-control-unit-sauna/506565)
**Status:** Official HA integration added in HA 2025.12

The Saunum controller uses **Modbus TCP over WiFi**. The key detail: **the manufacturer provided the protocol documentation directly**.

**Lesson:** Sometimes you don't need to reverse-engineer anything. It's worth asking Sauna360 if they'd share API documentation. The worst they can say is no.

---

### 5. Effe ECC Sauna — Local TCP Binary Protocol

**HA Community:** [Effe ECC Sauna — Reverse Engineered TCP Protocol](https://community.home-assistant.io/t/effe-ecc-sauna-unofficial-local-integration-reverse-engineered-tcp-protocol/994093)

The Effe ECC controller exposes a **local TCP port (8899)** on an ESP32 chip. Discovered by intercepting Android app traffic. Provides ON/OFF and light control, but states are tracked optimistically (the protocol doesn't expose current state in responses).

**Lesson:** If SaunaLogic2 has an ESP chip, it might expose a local TCP port. Worth port-scanning.

---

### 6. Cloud-Free Sauna Control — Hardware Bypass

**HA Community:** [Cloud-free sauna heater control](https://community.home-assistant.io/t/cloud-free-sauna-heater-control/962070)

A user built a completely independent ESP32 + relay + DS18B20 temperature sensor solution that **bypasses the SaunaLogic2 entirely**. No protocol reverse engineering — just hardware bypass.

Motivated by concerns about SaunaLogic2's cloud dependency and "enshittification."

**Lesson:** There is real community demand for cloud-free Finnleo sauna control. We're not alone.

---

## Protocol Comparison Table

| Sauna | Protocol | Encryption | Local? | Auth | Status |
|-------|----------|-----------|--------|------|--------|
| Huum UKU | Raw TCP | **None** | Via DNS redirect | None | RE'd, local server built |
| Huum (cloud API) | HTTPS REST | TLS | No (cloud) | Basic Auth | Official HA integration |
| Sauna360/Finnleo (RS485) | RS485 serial | N/A (wired) | Yes (hardware) | None | ESPHome component exists |
| Harvia Xenio | MQTT | TLS (port 8883) | No (cloud) | Unknown | HACS integration |
| Saunum Leil | Modbus TCP | None | Yes (WiFi) | None | Official HA integration |
| Effe ECC | Raw TCP | Unknown | Yes (port 8899) | None | Community integration |
| Finnleo SaunaLogic2 | **Unknown** | **Likely TLS** | **Unknown** | **Unknown** | **THIS PROJECT** |

---

## Other Resources

### Huum Ecosystem
- [horemansp/HUUM](https://github.com/horemansp/HUUM) — Simple Python scripts for the Huum cloud API with well-documented status codes
- [Chris-656/ioBroker.huum-sauna](https://github.com/Chris-656/ioBroker.huum-sauna) — ioBroker adapter, notable for implementing reduced polling when sauna is off (30-minute intervals)
- [KNX Forum: Gira HS4 and HUUM API](https://knx-user-forum.de/forum/%C3%B6ffentlicher-bereich/knx-eib-forum/knx-einsteiger/1966319-gira-hs4-and-huum-api) — KNX integration discussion

### HA Community Threads
- [Tylo Helo Sauna Controller Elite Integration](https://community.home-assistant.io/t/tylo-helo-sauna-controller-elite-integration/649909) — RS485-based approach, same protocol family
- [Integration of HUUM UKU Wifi](https://community.home-assistant.io/t/integration-of-huum-uku-wifi/312102) — The original community thread that led to the official Huum integration

---

## Attack Vectors for SaunaLogic2

Based on this landscape survey, we have **three viable approaches**, in order of preference:

### 1. Cloud API Interception (mitmproxy) — Most Likely Path
Intercept the SaunaLogic app's HTTPS traffic to document the cloud API. Build a Python client library. Build an HA integration.

**Pros:** No hardware modification, non-destructive, yields a cloud API client usable by anyone
**Cons:** Likely requires SSL pinning bypass, cloud-dependent, subject to API changes

### 2. RS485 Bus Tapping (ESP32 + MAX485) — Best Outcome
If the SaunaLogic2 uses an OLEA 103 board internally, the RS485 protocol is already documented by esphome-sauna360.

**Pros:** Fully local, cloud-free, existing protocol documentation
**Cons:** Requires opening the controller, hardware modification, may void warranty, not applicable to all users

### 3. Contact Sauna360 Directly — Easiest Path
Ask Sauna360 for API documentation. Saunum did this and got official HA integration support.

**Pros:** Sanctioned, documented, sustainable
**Cons:** May be refused, may take a long time, may require NDA or partnership
