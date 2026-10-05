# GlanceBar

A tiny macOS **menu-bar app** that shows the things you actually glance at — battery time, charger wattage, and live network speed — in a single status-bar item, plus a one-click **Keep Awake** toggle.

```
10:38  ↓991K ↑4K          ← on battery: 10 h 38 m left
⚡1:12 65W  ↓1.2M ↑88K     ← charging: 72 min to full, 65 W charger
⚡Full  ↓0 ↑0              ← charged, still plugged in
```

No Dock icon, no window — it lives entirely in the menu bar. Built in Swift with AppKit, no third-party dependencies.

---

## Features

- **Battery time, not just percent.** Shows time-to-full while charging and time-remaining on battery (`pmset`). The percentage is deliberately left out of the title because the stock macOS battery icon already shows it — except as a fallback during the ~1–2 minutes after plugging/unplugging when macOS reports `(no estimate)`, where it shows `%` so the readout is never blank.
- **Charger wattage.** Live adapter watts (e.g. `65W`) while plugged in, read instantly from IOKit via `ioreg` (not the slow `system_profiler`).
- **Network speed.** Live down/upload throughput, auto-scaled (`B`/`K`/`M`/`G` per second), sampled every 2 s directly from kernel interface counters.
- **Keep Awake (⌘K).** Toggles `caffeinate -dimsu` to prevent display/system sleep; the process is held and cleaned up on quit. A checkmark shows when it's active.
- **Steady title.** Uses monospaced digits so the menu-bar item doesn't jitter as the numbers change width.

Click the item for a dropdown with the full-precision readings, the Keep Awake toggle, Refresh (⌘R) and Quit (⌘Q).

---

## How it works

| Reading | Source | Cadence |
|---|---|---|
| Battery %, state, time-to-full/empty | `pmset -g batt` | 10 s |
| Charger wattage | `ioreg -r -c AppleSmartBattery` → `AdapterDetails.Watts` | 10 s |
| Network throughput | `getifaddrs()` → `if_data.ifi_ibytes/ifi_obytes`, summed over `en*` interfaces and diffed | 2 s |
| Keep Awake | `/usr/bin/caffeinate -dimsu` held as a child process | on toggle |

Only physical `en*` interfaces (Wi-Fi / Ethernet) are summed, so VPN tunnels (`utun*`) and loopback aren't double-counted. Counter wrap/reset is clamped to a non-negative delta.

It's a single-file app: [`Sources/GlanceBar/main.swift`](Sources/GlanceBar/main.swift).

---

## Install

Requires the Swift toolchain (Xcode or Command Line Tools: `xcode-select --install`).

```bash
git clone <this-repo> GlanceBar
cd GlanceBar
./scripts/install.sh
```

`install.sh` builds a release binary, wraps it in `~/Applications/GlanceBar.app` (an `LSUIElement` agent app — menu-bar only, no Dock icon), ad-hoc code-signs it, and installs a **per-user LaunchAgent** so it starts at login and relaunches if it ever crashes (but a normal **Quit** stays quit). No `sudo` required — everything lives in your home folder.

### Manual build

```bash
swift build -c release
./.build/release/GlanceBar      # run in foreground to try it
```

---

## Manage

```bash
# restart (e.g. after rebuilding)
launchctl kickstart -k gui/$(id -u)/com.local.GlanceBar

# stop until next login (or use the Quit menu item)
launchctl bootout gui/$(id -u)/com.local.GlanceBar

# uninstall completely (removes app + LaunchAgent)
./scripts/uninstall.sh
```

---

## FAQ

**Can it limit charging to 80 / 85 %?**
No — and by design. Capping the charge level means writing to the SMC (the power controller) as **root**, which is not something a menu-bar app should do. Use Apple's built-in setting (**System Settings → Battery → Charging**, which offers 80 % / Optimized) for the safe first-party option, or a purpose-built tool like [`battery`](https://github.com/actuallymentor/battery) or [`batt`](https://github.com/charlie0129/batt) for a custom percentage.

**Why no percentage in the title?**
The stock macOS battery icon already shows it. GlanceBar shows the thing macOS *doesn't* put in the menu bar — the estimated time — and only falls back to `%` when macOS has no time estimate.

**Light/dark mode?**
The title is plain text, so it follows the menu bar in both themes automatically.

---

## Background

GlanceBar started life as **ChargerWattage**, a one-reading wattage app, and grew into a combined power + network glance tool. Two notable fixes along the way:

- The original delegate was created inline (`app.delegate = AppDelegate()`); since `NSApplication.delegate` doesn't retain, it was deallocated immediately and `applicationDidFinishLaunching` never ran. Fixed by holding a strong reference and calling `app.run()`.
- Builds were blocked by a corrupted Command Line Tools install (a stale 2023 `module.modulemap` colliding with the current `bridging.modulemap`, plus mismatched compiler/SDK versions) — resolved by reinstalling the Command Line Tools.

---

## License

MIT — see [LICENSE](LICENSE).
