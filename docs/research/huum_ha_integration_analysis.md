<!--
Copyright 2026 Chris Keeser
SPDX-License-Identifier: Apache-2.0
-->
# Huum Home Assistant Integration — Technical Analysis

## Overview

The Huum HA integration exists as two separate codebases:
1. **`pyhuum`** — Standalone async Python API client library ([GitHub](https://github.com/frwickst/pyhuum), [PyPI](https://pypi.org/project/huum/))
2. **`homeassistant/components/huum/`** — HA core integration ([GitHub](https://github.com/home-assistant/core/tree/dev/homeassistant/components/huum))

**Maintainers:** frwickst, vincentwolsink
**Added in:** HA 2024.2
**Active installations:** ~170
**IoT class:** Cloud Polling
**Quality scale:** Bronze

---

## The pyhuum Library (v0.8.1)

### API Endpoints

All endpoints live under `https://sauna.huum.eu/action/home/`:

| Endpoint | Method | Body | Purpose |
|----------|--------|------|---------|
| `status` | GET | — | Get full sauna state |
| `start` | POST | `{"targetTemperature": N, "humidity": N}` | Turn on sauna |
| `stop` | POST | — | Turn off sauna |
| `light` | GET | — | Toggle light (no force on/off) |

### Authentication
**HTTP Basic Auth** with Huum app email and password on every request.

```python
self.auth = aiohttp.BasicAuth(username, password)
# Used in every API call:
call_args = {"url": url, "auth": self.auth}
```

### Status Response Schema

```python
@dataclass
class HuumStatusResponse:
    status: int              # statusCode — see SaunaStatus enum
    door_closed: bool        # door — sauna door sensor
    temperature: int         # current temperature (Celsius)
    sauna_name: str          # saunaName
    target_temperature: int  # targetTemperature (None when off)
    start_date: int          # startDate — Unix timestamp
    end_date: int            # endDate — Unix timestamp
    duration: int            # session duration
    config: int              # 1=steamer, 2=light, 3=both
    steamer_error: int       # steamerError
    light: int               # 0 or 1
    target_humidity: int     # targetHumidity (0-10)
    humidity: int            # current humidity
    sauna_config: SaunaConfig  # nested config object
```

### Sauna Config Schema

```python
@dataclass
class SaunaConfig:
    child_lock: str
    max_heating_time: int
    min_heating_time: int
    max_temp: int           # Controller's max temperature setting
    min_temp: int           # Controller's min temperature setting
    max_timer: int
    min_timer: int
```

### Status Codes

```python
class SaunaStatus(IntEnum):
    OFFLINE = 230
    ONLINE_HEATING = 231
    ONLINE_NOT_HEATING = 232
    LOCKED = 233            # Locked by another user
    EMERGENCY_STOP = 400
```

### Safety Logic
Before turning on the heater, `pyhuum` checks if the door is closed:

```python
async def _check_door(self) -> None:
    status = await self.status()
    if not status.door_closed:
        raise SafetyException("Can not start sauna when door is open")
```

This can be bypassed with `safety_override=True`.

---

## HA Integration Architecture

### File Structure
```
homeassistant/components/huum/
├── __init__.py          # Entry setup, coordinator init
├── manifest.json        # Metadata, requirements
├── const.py             # DOMAIN, platform list, config constants
├── coordinator.py       # DataUpdateCoordinator (30-second polling)
├── entity.py            # HuumBaseEntity (shared device info)
├── config_flow.py       # Username/password UI setup + reauth
├── climate.py           # Climate entity (HEAT/OFF, target temp)
├── sensor.py            # Temperature sensor
├── binary_sensor.py     # Door open/closed sensor
├── light.py             # Light control (on/off, toggle-based)
├── number.py            # Steamer/humidity control (0-10)
└── strings.json         # UI strings
```

### Platform → Entity Mapping

| Platform | Entity Class | Unique ID | What It Does |
|----------|-------------|-----------|--------------|
| `climate` | `HuumDevice` | `{entry_id}` | HEAT/OFF modes, target temp (40-110°C), current temp |
| `sensor` | `HuumTemperatureSensor` | `{entry_id}_temperature` | Current temperature reading |
| `binary_sensor` | `HuumDoorSensor` | `{entry_id}_door` | Door open/closed state |
| `light` | `HuumLight` | `{entry_id}` | Light on/off (conditional: only if config includes light) |
| `number` | `HuumSteamer` | `{entry_id}` | Humidity duty cycle 0-10 (conditional: only if config includes steamer) |

### Data Update Coordinator

```python
UPDATE_INTERVAL = timedelta(seconds=30)

class HuumDataUpdateCoordinator(DataUpdateCoordinator[HuumStatusResponse]):
    def __init__(self, hass, config_entry):
        self.huum = Huum(
            config_entry.data[CONF_USERNAME],
            config_entry.data[CONF_PASSWORD],
            session=async_get_clientsession(hass),
        )

    async def _async_update_data(self) -> HuumStatusResponse:
        return await self.huum.status()
```

All entities inherit from `HuumBaseEntity` → `CoordinatorEntity`, which means they all share the same polling cycle and data object. No redundant API calls.

### Climate Entity Details

```python
class HuumDevice(HuumBaseEntity, ClimateEntity):
    _attr_hvac_modes = [HVACMode.HEAT, HVACMode.OFF]
    _attr_supported_features = (
        ClimateEntityFeature.TARGET_TEMPERATURE
        | ClimateEntityFeature.TURN_OFF
        | ClimateEntityFeature.TURN_ON
    )
    _attr_target_temperature_step = PRECISION_WHOLE  # 1°C steps
    _attr_temperature_unit = UnitOfTemperature.CELSIUS
```

When `HVACMode.HEAT` is set, it calls `huum.turn_on(temperature)`.
When `HVACMode.OFF` is set, it calls `huum.turn_off()`.
After any command, it calls `coordinator.async_refresh()` for immediate state update.

### Config Flow

Simple username/password flow:
1. User enters email and password (same as Huum mobile app)
2. Integration calls `huum.status()` to validate credentials
3. On success, creates the config entry
4. Supports re-authentication if credentials expire

---

## Known Issues & Bugs

### Critical: Status Polling Cancels Sauna Sessions
**Source:** [HA Community Thread, Page 4](https://community.home-assistant.io/t/integration-of-huum-uku-wifi/312102/4)

Opening Home Assistant with the Huum integration loaded was reported to **cancel active sauna sessions** that were started through the Huum app. The status polling endpoint may have had side effects.

**Lesson for us:** Never trust that a "status" endpoint is read-only. Test thoroughly.

### Fahrenheit Not Supported
**Issue:** [#129012](https://github.com/home-assistant/core/issues/129012)

Temperature validation is hardcoded to the Celsius range (40-110). Setting 120°F gets rejected because it's validated against the Celsius bounds. Still open.

**Lesson for us:** Implement unit conversion from day one. HA handles display conversion, but the API client must accept the correct range for the configured unit system.

### Zero Temperature Bounds from API
**Issue:** [#152717](https://github.com/home-assistant/core/issues/152717) → **Fix:** [PR #153871](https://github.com/home-assistant/core/pull/153871)

The Huum API sometimes returns `0` for min/max temperature, causing a "Temperature must be between 0 and 0" error. Fixed by defaulting to 40-110°C when the API returns garbage.

**Lesson for us:** Always have sensible fallback defaults. Cloud APIs return unexpected values.

### No hvac_action Reported
**Issue:** [#156394](https://github.com/home-assistant/core/issues/156394)

The climate entity doesn't distinguish between "actively heating" and "at temperature, idle." The API has distinct status codes (231=heating, 232=idle) but the integration doesn't map them to `hvac_action`.

**Lesson for us:** Implement `HVACAction.HEATING` / `HVACAction.IDLE` / `HVACAction.OFF` from the start.

### Max Temp Sync Delay
**Issue:** [#160264](https://github.com/home-assistant/core/issues/160264)

When the max temperature is changed on the physical controller, the API takes ~10 minutes to reflect the new value.

**Lesson for us:** Cloud APIs are not real-time. Design the integration to handle stale data gracefully.

---

## Design Patterns Worth Adopting

1. **Separate PyPI library + HA integration** — HA core requires this separation. The library handles API communication, the integration handles HA-specific concerns.

2. **DataUpdateCoordinator pattern** — Single polling loop, all entities read from the same data object. No redundant API calls.

3. **Conditional entity creation** — Light and steamer entities only created if the sauna's config flag indicates those features exist.

4. **Safety checks in the library** — Door-closed verification before heater activation. Raises a specific exception that the HA integration catches and converts to `HomeAssistantError`.

5. **Reauth support** — If credentials expire, the integration prompts for re-authentication instead of silently failing.

---

## What We'd Do Differently for Finnleo

| Huum Approach | Our Improvement |
|---------------|-----------------|
| Cloud polling only | Prefer local API if one exists |
| 30-second fixed polling | Adaptive polling (faster when heating, slower when off) |
| No hvac_action | Full HEATING/IDLE/OFF action reporting |
| Celsius-only validation | Unit-aware temperature handling |
| Toggle-only light control | Force on/off if API supports it |
| No timer entity | Timer entity (number or datetime) |
| No delay start | Delay start entity |
| Single sauna per account | Multi-sauna support |
