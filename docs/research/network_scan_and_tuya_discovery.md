# Network Scan & Tuya Device Discovery

## Date: 2026-03-22

## How We Found the Sauna

### Methodology

1. **Gathered unknown IP addresses** from the router's DHCP lease table
2. **MAC vendor lookups** to identify chip manufacturers (Espressif, Silicon Labs, etc.)
3. **Port scanning** common IoT ports (80, 443, 6668, 8883, 1883, 5353, etc.)
4. **Protocol probing** on open ports with 10 different handshakes (HTTP, MQTT, WebSocket, JSON, TLS, binary Tuya/Huum-style greetings, RS485 frames)
5. **tinytuya UDP scan** to discover all Tuya devices broadcasting on ports 6666/6667

### Key Discovery: Tuya Protocol on Port 6668

One device responded to our probes with unmistakable Tuya protocol v3.3 frames:

```
00 00 55 AA ... 33 2E 33 ... 00 00 AA 55
```

- `00 00 55 AA` = Tuya header magic bytes
- `33 2E 33` = "3.3" = Tuya protocol version
- `00 00 AA 55` = Tuya footer magic bytes

We initially dismissed this as "just a Tuya smart plug" — the laughable mistake that would haunt us. After the APK decompilation revealed SaunaLogic IS Tuya, we came back to this device and confirmed via the SaunaLogic app's device info page that it was indeed the sauna.

### tinytuya Network Scan

Running `python -m tinytuya scan` from a machine on the local network discovered all Tuya devices. The sauna appeared with:
- **Product ID:** `acl5qrawgmjajabn` (unique among the devices — all the smart plugs shared different product IDs)
- **Protocol:** v3.3
- **Port:** 6668

### Identifying the Sauna

The final confirmation came from the SaunaLogic app's device info screen, which showed the MAC address matching the Espressif device we'd found on the network. The device name: **Björn**.

## SaunaLogic App Network Diagnostic

The SaunaLogic app has a built-in network diagnostic tool that reveals useful information:

```
App name: SaunaLogic
App version: 1.1.0
App build: 20250718150442
App bundle ID: com.tyloheloinc.saunalogic
```

Key findings from the diagnostic:
- **Tuya Cloud Region:** US West (AWS us-west-2)
- **API Domain:** Resolves to AWS IP addresses in the us-west-2 region
- **MQTT Domain:** Separate from the API domain, also AWS us-west-2
- The app uses both REST API and MQTT for device communication

## The OEM Account Isolation Problem

The SaunaLogic app creates a **separate Tuya OEM account** (appId 15909) that is completely isolated from a standard Smart Life/Tuya Smart account. Even with the same email address, the accounts are separate with different passwords and no shared devices.

### Approaches That Failed

1. **Link SaunaLogic QR code** — The Tuya developer console's "Link App Account" QR code was rejected by the SaunaLogic app: "please use the designated APP to scan the code to log in"
2. **Share device to Smart Life** — The share link (`smart321.com`) is bound to the SaunaLogic OEM app and cannot be opened in Smart Life
3. **Tuya Cloud API with extracted SDK keys** — The SDK keys from the APK (THING_SMART_APPKEY, appEncryptKey) are NOT the same as Cloud API Access ID/Secret. All attempts returned "clientId is invalid" or "sign invalid"
4. **Log into Smart Life with SaunaLogic credentials** — Different passwords, login fails
5. **tinytuya local probe without key** — Error 914: "Check device key or version"

### What Worked: Re-Pairing to Smart Life

The solution was to remove the device from SaunaLogic and re-pair it directly to the Smart Life app:

1. Put the SL2 in pairing mode (two-press Bluetooth button → "CON1" on display)
2. Device creates a `SmartLife-XXXX` WiFi hotspot
3. In Smart Life app, use **manual add** with **AP Mode** (not auto-scan — auto-scan can't find AP mode devices)
4. Connect phone to the SmartLife hotspot, return to Smart Life app
5. Device pairs and appears in the Smart Life account

**Important:** Smart Life's auto-scan does NOT find AP mode devices. You must go through the manual add flow and select "AP Mode" or "Compatible Mode (AP)" — this option is easy to miss in the UI.

After pairing, the device appeared in the Tuya developer project with its local key, enabling cloud-free local control via `tuya_local`.
