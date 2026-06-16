# WC26 — World Cup 2026 Live Scores in your Mac menu bar

A tiny native macOS menu-bar app that shows live FIFA World Cup 2026 scores, glanceable from anywhere.

![menu bar](https://img.shields.io/badge/macOS-13%2B-blue) ![swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Live scores in the menu bar** — the current/next match shows right in the bar; click for the full day.
- **2-column grid** of all matches for any day, with country flags.
- **Per-game ⚡ quick-refresh** — star a live game to poll it every 12s; everything else refreshes every 60s.
- **Full tournament schedule** — a date strip from the opener (Jun 11) through the Final (Jul 19), with round labels.
- **Tap a team** — the 3-letter code opens an English Google search; the Chinese name opens a Chinese one.
- **Global show/hide shortcut** — default `⌃\`` (Control + backtick), rebindable in Settings. No Accessibility permission needed.

Data comes from ESPN's public scoreboard endpoint. No API key, no account, no tracking.

## Install

1. Download `WC26.zip` from the [latest release](../../releases/latest) and unzip it.
2. Move `WC26.app` to `/Applications`.
3. **First launch** (required, because the app isn't notarized): **right-click `WC26.app` → Open**, then click **Open** in the dialog. macOS remembers this and won't ask again.
   - If macOS still refuses, run once in Terminal: `xattr -dr com.apple.quarantine /Applications/WC26.app`

The app lives only in the menu bar (no Dock icon). To launch at login: System Settings → General → Login Items → add WC26.

## Usage

- **Show/hide:** press `⌃\`` or click the score in the menu bar.
- **Change the shortcut:** open the panel → **Settings** tab → click the shortcut field → press your combo (Esc cancels, Delete clears).
- **Quick-refresh a game:** click the ⚡ on any match; it polls every 12s while that game is live.
- **Browse dates:** tap any day in the strip. The menu-bar title keeps showing today's live score even while you browse.

## Build from source

Requires Xcode command-line tools (Swift 5.9+).

```sh
./build.sh        # compiles WC26.swift into WC26.app
open WC26.app
```

Everything is a single file: [`WC26.swift`](WC26.swift).

## Notes

- Scores are as fresh as ESPN's feed (~20–30s server-side); the app polls every 12s for starred live games.
- Times and the daily schedule are shown in **your local timezone**.
- Not affiliated with FIFA or ESPN.

## License

MIT — see [LICENSE](LICENSE).
