<!--
Copyright 2026 Chris Keeser
SPDX-License-Identifier: Apache-2.0
-->
# SaunaLogic APK Decompilation — Findings

## THE HEADLINE: SaunaLogic is a Tuya White-Label App

The SaunaLogic Android app (`com.tyloheloinc.saunalogic`) is built entirely on the **Tuya IoT Platform** (branded as "ThingClips" / "Thing Smart"). Sauna360 did not build a custom cloud backend — they used Tuya's OEM platform to create a branded app on top of Tuya's infrastructure.

This is the single most important finding of the entire reverse engineering effort.

---

## What This Means

### For Our Integration
1. **We may not need to reverse-engineer anything.** The official Tuya HA integration already exists and supports thousands of Tuya devices. If we can link the SaunaLogic2 to a Tuya developer account, it might "just work."

2. **Local control is possible** via the Tuya Local protocol (the protocol we already probed on port 6668). The `localtuya` HACS integration supports local control of Tuya devices without cloud dependency.

3. **The cloud API is Tuya's well-documented API** at https://developer.tuya.com/. The API supports device control, status queries, and automation.

4. **The device data points (DPs) are the key.** Every Tuya device exposes its capabilities as numbered "data points." We need to discover what DPs the SaunaLogic2 uses (e.g., DP 1 = power, DP 2 = target temperature, etc.).

### The Tuya Connection
- **Tuya** is the world's largest IoT platform (500M+ devices). They provide a complete white-label solution: hardware modules, cloud backend, mobile app framework, and voice assistant integrations.
- Sauna360 used Tuya's OEM program to build the SaunaLogic app. Tuya provides the entire app framework (ThingClips SDK), and the manufacturer just customizes branding, device categories, and UI.
- This is why SaunaLogic2 supports Google Home and Alexa — Tuya's platform provides these integrations out of the box.

---

## Extracted Configuration

### From `ThingNGConfig.java`:

```java
public static final int appId = 15909;
public static final int packageId = 1144800412;
public static final String region = "International";
public static final String app_scheme = "tyloheloincsaunalogic";
public static final String version = "1.1.0";
public static final String base_version = "odm/v6.7.0";
public static final String buildEnv = "prod";
public static final String countryCodes = "{\"EU\":[91]}";
public static final String csa_vid = "4701";  // Matter CSA Vendor ID
public static final String gcm_sender_id = "<REDACTED>";
public static final String google_maps_key = "<REDACTED>";
public static final String platform = "android";
public static final boolean use_ssl_pinning = true;
public static final boolean securityOpen = true;
public static final String push_factory = "typush";  // Tuya push notifications
public static final boolean is_siri_support = true;
public static final boolean is_alexa_to_thingpp_support = true;
public static final String ap_mode_ssid = "SmartLife";  // The pairing hotspot name
```

### Encryption Keys (for Tuya SDK initialization):
```java
// Debug environment
public static final String appEncryptKeyDebugV2 = "<REDACTED>";
public static final String appEncryptSecretDebugV2 = "<REDACTED>";

// CV Production environment
public static final String appEncryptKeyCvProdV2 = "<REDACTED>";
public static final String appEncryptSecretCvProdV2 = "<REDACTED>";

// Encryption key
public static final String encryptionKey = "<REDACTED>";

// Android package signatures
public static final String android_package_signs = "<REDACTED>";
```

### App SDK Initialization (from `SmartApplication.java`):
```java
ThingSmartSdk.init(this);
ThingSmartSdk.setLocationSwitch(false);

// App key and secret loaded from BuildConfig
str = BuildConfig.THING_SMART_APPKEY;
str2 = BuildConfig.THING_SMART_SECRET;

// SSL pinning enabled
supportSSLPinning(getResources().getBoolean(R.bool.use_ssl_pinning))
```

### From `AndroidManifest.xml`:
```xml
<meta-data android:name="region" android:value="international"/>
<meta-data android:name="UMENG_CHANNEL" android:value="international"/>
```

---

## Architecture

The app is structured as a Tuya OEM app:

```
com.tyloheloinc.saunalogic   — Package name (Sauna360's branding)
├── com.smart.app             — App initialization (Tuya template code)
│   ├── SmartApplication      — Main Application class
│   ├── ThingNGConfig         — Tuya OEM configuration (appId, keys, features)
│   └── MultiProcessInit      — Region and multi-process setup
├── com.thingclips.*          — Tuya SDK (ThingClips platform)
│   ├── smart.home.sdk        — Home/device management
│   ├── smart.android.base    — ThingSmartSdk core
│   ├── smart.android.network — Network communication
│   ├── smart.camera          — Camera support (unused for sauna)
│   ├── smart.security        — Security/alarm features
│   └── sdk.device            — Device control and data points
├── com.smart.ThingSplashActivity — Splash screen
└── [Tuya framework libraries] — OkHttp, Retrofit, RxJava, etc.
```

The R.java file is ~385 lines of pure configuration. The actual sauna-specific logic is handled by Tuya's "mini-app" and "device panel" system — the sauna control UI is loaded dynamically from Tuya's cloud, not baked into the APK.

---

## SSL Pinning

```java
public static final boolean use_ssl_pinning = true;
public static final boolean securityOpen = true;
```

SSL pinning is enabled. This means mitmproxy interception of the app's traffic would require:
1. Frida + objection to bypass pinning on a rooted device, OR
2. Modifying the APK to disable pinning, OR
3. Using the Tuya developer API directly (bypassing the app entirely)

Given that this is a Tuya device, option 3 (Tuya developer API) is by far the best approach.

---

## Notable Feature Flags

```java
is_google_home_support = false   // Interesting — disabled in app config?
is_alexa_to_thingpp_support = true  // Alexa via Tuya's platform
is_siri_support = true
is_matter_support = false  // No Matter support yet
is_echo_support = false
is_support_google_home_app_api = false
```

Note: `is_google_home_support = false` is interesting because the SaunaLogic2 product page advertises Google Home support. This flag may control whether Google Home linking is done through the app or through Tuya's cloud platform directly.

---

## Network Scan Update: Tuya Devices Found

During our network scan, we probed `<sauna-ip>` (ESP_XXXXXX) on port 6668 and received a **Tuya protocol v3.3 response**:

```
00 00 55 AA ... 33 2E 33 ... 00 00 AA 55
```

- `00 00 55 AA` = Tuya header magic bytes
- `33 2E 33` = "3.3" = Tuya protocol version
- `00 00 AA 55` = Tuya footer magic bytes

This confirms there are Tuya devices on the network. However, <sauna-ip> may or may not be the sauna — it could be any Tuya device. To identify which Tuya device is the SaunaLogic2, we need to:
1. Check the Tuya developer portal for linked devices
2. Or match device IDs from the SaunaLogic app

---

## Next Steps

1. **Create a Tuya IoT developer account** at https://iot.tuya.com/
2. **Link the SaunaLogic app account** to the Tuya developer platform using the "Link Tuya App Account" feature
3. **Discover the device's data points (DPs)** — this tells us what the sauna exposes (power, temp, timer, light, etc.)
4. **Try the official Tuya HA integration** — it might already support the SaunaLogic2 with zero custom code
5. **Try LocalTuya** (HACS) for local control without cloud dependency
6. **If needed**, build a custom integration that maps sauna-specific DPs to HA climate/switch/sensor entities
