# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **Control4 DriverWorks driver** for Android TV/media player devices. It enables IP-based remote control of Android devices through the Control4 home automation system using UDP commands. Driver version 2, targeting Control4 OS 2.8.2+.

## Building & packaging

```bash
./package_driver.sh
```

This zips `driver.lua` + `driver.xml` and renames the output to `AndriodRemote.c4z`. To deploy, upload the `.c4z` to the Control4 controller via Composer Pro.

Manual equivalent (if the script fails):
```bash
zip AndriodRemote.zip driver.lua driver.xml
mv AndriodRemote.zip AndriodRemote.c4z
```

## Architecture

The driver follows the standard Control4 two-file pattern:

- **`driver.xml`** — All metadata, proxy bindings, configurable properties, UI controls, and connection definitions. Defines three proxy bindings:
  - `5001` — `media_service` ("Android Apps") — app launching
  - `5002` — `media_player` ("Android") — playback control
  - `5003` — `avswitch` ("Android App Switcher") — app switching UI
- **`driver.lua`** — All runtime logic. Control4 calls into this via the DriverWorks Lua API.

## Key Lua implementation details

**Entry points** (called by Control4 runtime):
- `OnDriverInit()` / `OnDriverDestroyed()` — lifecycle hooks
- `OnPropertyChanged(propertyName)` — handles config changes from Composer (IP, port, timing, etc.)
- `ReceivedFromProxy(bindingID, command, params)` — main command dispatcher; all proxy commands arrive here

**Command routing in `ReceivedFromProxy`:**
1. `PASSTHROUGH` — extracts raw command from params and sends via UDP
2. `LAUNCH_APP` — maps app name to `openApp <appname>` UDP command
3. `START_LONG_PRESS` / `STOP_LONG_PRESS` — directional hold handling
4. All other commands — looked up in a static table and sent via UDP

**Long-press mechanism** (`StartLongPress` / `StopLongPress`):
- Uses a session ID (`os.time() + math.random()`) stored in `activeSessionId` to prevent race conditions between overlapping press/release events
- Sends the initial keypress immediately, then repeats via `C4:SetTimer` at the configured interval
- Session validation in `OnRepeatTimer` stops stale timers automatically

**UDP communication** (`InitUDP` / `SendUDP`):
- Non-blocking socket (`settimeout(0)`) on the configured IP/port
- Default target: `192.168.1.64:1028`
- Re-initializes socket on IP/port property change

## Configurable properties (set in Composer)

| Property | Default | Notes |
|---|---|---|
| Device IP | 192.168.1.64 | Android device IP |
| Device Port | 1028 | UDP port |
| Repeat Interval (ms) | 100 | Long-press repeat rate |
| Max Hold Duration (ms) | 3000 | Long-press cutoff |
| Debug Mode | Off | Enables `print()` logging |
| Polling Time | 15s | Composer heartbeat |
| Menu Button | Home | What MENU key does |
| On Power Off / On | Do Nothing | Post-power actions |

## Control4 / Lua notes

- Lua 5.3 with LuaJIT enabled (declared in XML)
- Use `C4:SetTimer` / `C4:KillTimer` for timers (not standard Lua)
- Use `C4:CreateUDPSocket` for networking
- `print()` goes to the Control4 log (only useful with Debug Mode on)
- The `.c4z` format is just a ZIP — can be inspected with any zip tool
