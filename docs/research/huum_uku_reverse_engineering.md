# Huum UKU WiFi Controller — Reverse Engineering Deep Dive

## Source
**Blog post:** ["Invading the Huum Uku Wifi Controller"](https://kaurpalang.com/posts/invading-the-sauna/) by Kaur Palang
**Published:** May 26, 2025
**Author's repo:** [kpalang/huum-controller](https://github.com/kpalang/huum-controller) (GPL-3.0)

---

## The Story

### Motivation
Kaur Palang found a home with a Huum UKU WiFi-controlled sauna. His core principle: **"I will not use any smartness on any device that I cannot control locally."** The dream was simple — arrive home from bad weather and step into a sauna that's already been heating for 1.5 hours to 90°C.

An existing HA integration existed (via the `pyhuum` library), but it worked through Huum's cloud API. That wasn't good enough. He wanted **direct local control** of the controller on his own network.

### The Approach

#### Step 1: Understanding the Architecture
Before touching any tools, the author reasoned through the architecture:
- The controller must initiate outbound connections (no inbound firewall rules needed for normal users)
- First idea: **port mirroring** on a network switch to capture traffic → **Dead end** because the UKU is WiFi-only (*"Uku WiFi..."*)
- Pivoted to: **laptop as WiFi hotspot** — the controller connects to the laptop's hotspot, laptop maintains wired internet, all controller traffic flows through the laptop

#### Step 2: Traffic Capture (~3 hours of Wireshark)
The author spent roughly **3 hours** looking for ways to read TLS-encrypted messages. This turned out to be completely unnecessary because...

**The Critical Discovery: NO TLS AT ALL.**

While examining a TCP frame in Wireshark, the ASCII view revealed plaintext:
```
UQ4-4-2.2.1213-4a1d6da1-4
UQ4 EU WiFi
```

These matched the firmware version and friendly name from the controller's info menu. The entire protocol was **unencrypted raw TCP**.

The author's reaction: *"I've yet to take a stance on whether I'm happy over the lack of TLS because it made my life so much easier, or furious that my heater could technically be controlled by someone other than myself (and Huum)."*

#### Step 3: Protocol Analysis

**Regular ping pattern:** Every ~4 minutes, the controller sends an 11-byte status message:
```
09 17 00 f8 23 00 00 00 00 00 00
```
- Byte 2 (`0x17` = 23) = current temperature in Celsius

**Physical button test:** The author pressed the physical power button, counted to "20 Mipsipipi" (an Estonian counting method — [YouTube reference](https://youtu.be/KULE3UDdr34?si=BLfk9ogyn9Wm3jCX&t=73)), and turned it off.

Turn on packet:
```
08 5a 00 00 00 00 03 11 6c 2c 68 41 96 2c 68 13 6c 2c 68 00 00 00 00 01 00
```

Turn off packet (27 seconds later):
```
08 5a 00 00 00 00 03 00 00 00 00 00 00 00 00 2e 6c 2c 68 00 00 00 00 01 00
```

Key deductions:
- `0x08` = message type for heater control
- `0x5a` = 90 decimal = target temperature of 90°C
- Groups of 4 bytes = little-endian Unix timestamps
- Turning off zeros out the start/stop timestamp fields

#### Step 4: Protocol Identification — Three Hypotheses

1. **MQTT** — Rejected. Payloads too small to contain pub-sub topic metadata.
2. **WebSocket** — Built a Bun WebSocket server, got `HTTP/1.1 505 HTTP Version Not Supported`. The controller doesn't speak HTTP at all.
3. **Raw TCP** — Confirmed. Simple, direct TCP socket communication.

#### Step 5: DNS Redirection
The controller does a DNS lookup for `api.huum.eu` when it connects to WiFi. Using **AdGuard Home**, the author added a DNS rewrite pointing `api.huum.eu` → `192.168.1.146` (his local server). This redirected all controller traffic to his own machine.

#### Step 6: Local Server Implementation
Built a replacement server in **Bun** (TypeScript) consisting of:
- **TCP socket server** — speaks the binary protocol with the controller
- **HTTP REST API** — exposes endpoints for external control (HA, scripts, etc.)

During implementation, discovered **message type 0x02** — allows setting the controller's status report frequency (0-255 seconds). Also forces an immediate state update when sent. The author called this *"Absolutely Home Assistantable!"*

---

## Complete Protocol Specification

### Communication Flow
```
1. Controller connects to WiFi
2. DNS lookup: api.huum.eu
3. TCP connection established
4. Controller → Server: 0x0B (greeting with firmware version + device name)
5. Server → Controller: 0x02 (set ping frequency, triggers immediate state report)
6. Controller → Server: 0x09 (current temperature + heater status)
7. Controller → Server: 0x08 (heater target temp + timestamps)
8. [Periodic loop]: Controller → Server: 0x09 at configured frequency
9. [On command]: Server → Controller: 0x07 (heater control)
10. [After command]: Controller → Server: 0x08 (acknowledge state change)
```

### Message Types

#### 0x02 — Set Ping Frequency
**Direction:** Server → Controller
**Purpose:** Set how often the controller reports status. Can be sent anytime.

| Byte(s) | Meaning |
|---------|---------|
| `02` | Message ID |
| 4 bytes | Current timestamp (little-endian) |
| 1 byte | Delay in seconds (0-255) |
| `00` | Terminator |

**Example:** `02 3f 31 2e 68 fc 00` — set ping frequency to 252 seconds

#### 0x07 — Heater Control
**Direction:** Bidirectional (server ↔ controller)
**Purpose:** Turn heater on/off, set target temperature

| Byte(s) | Meaning |
|---------|---------|
| `07` | Message ID |
| 1 byte | Target temperature (hex = Celsius) |
| 4 bytes | Unknown padding (`00 00 00 00`) |
| 1 byte | Unknown (`03`) |
| 4 bytes | Heating started timestamp (LE) |
| 4 bytes | Heating stop timestamp (LE) |
| 4 bytes | Current timestamp (LE) |
| 4 bytes | Unknown values |
| `00` | Terminator |

**Turn off:** Zero out the start/stop timestamp fields.

**Note:** When the controller's physical button is pressed, the outgoing message uses `0x08` instead of `0x07`, but the structure is identical.

#### 0x08 — Cloud State Update
**Direction:** Controller → Server
**Purpose:** Report heater state changes back to the cloud
**Structure:** Identical to 0x07

#### 0x09 — Status Ping
**Direction:** Controller → Server
**Purpose:** Periodic temperature and status report

| Byte(s) | Meaning |
|---------|---------|
| `09` | Message ID |
| 1 byte | Current temperature (hex = Celsius) |
| 1 byte | Padding? (`00`) |
| 1 byte | Ping frequency in seconds |
| 1 byte | Heater status (observed: `0x23`, `0x24`, `0x25`) |
| 5 bytes | Padding? (`00 00 00 00 00`) |
| `00` | Terminator |

#### 0x0B — Server Greeting
**Direction:** Controller → Server
**Purpose:** Identify controller on connection

Contains firmware version string (e.g., `UQ4-4-2.2.1213-4a1d6da1-4`) and friendly name (e.g., `UQ4 EU WiFi`) in ASCII, padded with null bytes. The author admits: *"and some other stuff I'm too lazy to figure out."*

---

## Security Findings

1. **No TLS/encryption** — All traffic is plaintext raw TCP
2. **No authentication** — No login, tokens, or credentials exchanged
3. **No origin verification** — Commands accepted from any TCP connection
4. **Firmware disclosed** in plaintext on connection
5. **Timestamps control heating duration** — Could be manipulated
6. **Potential cross-device attack** — The author noted plans to test if he could control a friend's heater: *"I know a bloke who has an identical setup and lives not far from me."*

---

## Dead Ends & Failures

| Attempt | Outcome |
|---------|---------|
| Port mirroring on network switch | Controller is WiFi-only, no Ethernet |
| 3 hours hunting for TLS decryption | There was no TLS to decrypt |
| mitmproxy setup | Never needed — traffic was unencrypted |
| MQTT hypothesis | Payloads too small for pub-sub topics |
| WebSocket server | Controller rejected HTTP entirely (505) |
| dnsmasq for DNS redirect | Author *"broke the whole setup last time"*, used AdGuard Home instead |

---

## The Burnout
After getting everything working, the author hit the classic developer wall:

> *"I am at the boring part of this project - making everything pretty. I have more-or-less understood how the TCP communication works, I am successfully reading it, and also starting actions myself; I've found a way to force the controller to speak to my server, instead of Huum's proprietary one."*
>
> *"All that now remains is polishing the server code and pushing to GitHub... But **maaan** do I not feel like doing it..."*

The GitHub repo (`kpalang/huum-controller`) has only 2 commits. The interesting part was done. The boring part won.

---

## Key Lessons for Our SaunaLogic2 Effort

### What Transfers
1. **WiFi hotspot capture technique** — Laptop hotspot + Wireshark for traffic analysis
2. **DNS redirection** — Point the cloud domain to a local server
3. **Message-type-first protocol analysis** — Identify the first byte as message type, work outward
4. **Little-endian timestamps** — Common in IoT binary protocols
5. **Physical button testing** — Press the button, correlate packets with known actions

### What Won't Transfer
1. **No TLS** — The Huum was unusually insecure. SaunaLogic2 almost certainly uses TLS, especially since it integrates with Google Home and Alexa (which require HTTPS)
2. **Raw TCP protocol** — Modern IoT devices more commonly use MQTT over TLS or HTTPS REST APIs
3. **Simple binary encoding** — SaunaLogic2 likely uses JSON or Protocol Buffers

### What We Should Watch For
1. **Certificate pinning** in the SaunaLogic app — Will complicate mitmproxy interception
2. **The SaunaLogic2 may have an RS485 bus internally** — Same corporate family as the Tylo controllers that use RS485
3. **Google Home/Alexa integration implies a structured cloud API** — These platforms require standardized device trait schemas
