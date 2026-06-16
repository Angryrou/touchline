# Touchline — World Cup 2026 Live Scores in your Mac menu bar

A tiny native macOS menu-bar app that shows live FIFA World Cup 2026 scores, glanceable from anywhere.

![menu bar](https://img.shields.io/badge/macOS-13%2B-blue) ![swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Live scores in the menu bar** — the current/next match shows right in the bar; click for the full day.
- **2-column grid** of all matches for any day, with country flags.
- **Per-game ⚡ quick-refresh** — star a live game to poll it every 12s; everything else refreshes every 60s.
- **Auto-updating schedule** — when a game finishes, the app refreshes faster to pull in settled group standings and any newly-determined knockout fixtures.
- **Local timezone, always** — kickoff times and the daily schedule auto-adapt to your timezone (shown in the header, e.g. `EDT · UTC-4`). Nothing hardcoded.
- **Full tournament schedule** — a date strip from the opener (Jun 11) through the Final (Jul 19), with round labels.
- **Tap a team** — the 3-letter code opens an English Google search; the Chinese name opens a Chinese one.
- **Global show/hide shortcut** — default `⌃\`` (Control + backtick), rebindable in Settings. No Accessibility permission needed.
- **Settings** — launch at login, check for updates, source link.

Data comes from ESPN's public scoreboard endpoint. No API key, no account, no tracking.

## Install

1. Download `Touchline.zip` from the [latest release](../../releases/latest) and unzip it.
2. Move `Touchline.app` to `/Applications`.
3. **First launch** (required, because the app isn't notarized): **right-click `Touchline.app` → Open**, then click **Open** in the dialog. macOS remembers this and won't ask again.
   - If macOS still refuses, run once in Terminal: `xattr -dr com.apple.quarantine /Applications/Touchline.app`

The app lives only in the menu bar (no Dock icon). To launch at login: open the **Settings** tab and toggle **Launch at login** (or System Settings → General → Login Items).

## Usage

- **Show/hide:** press `⌃\`` or click the score in the menu bar.
- **Change the shortcut:** open the panel → **Settings** tab → click the shortcut field → press your combo (Esc cancels, Delete clears).
- **Quick-refresh a game:** click the ⚡ on any match; it polls every 12s while that game is live.
- **Browse dates:** tap any day in the strip. The menu-bar title keeps showing today's live score even while you browse.

## Build from source

Requires Xcode command-line tools (Swift 5.9+).

```sh
./build.sh        # compiles Touchline.swift into Touchline.app
open Touchline.app
```

Everything is a single file: [`Touchline.swift`](Touchline.swift).

## Notes

- Scores are as fresh as ESPN's feed (~20–30s server-side); the app polls every 12s for starred live games.
- Times and the daily schedule are shown in **your local timezone**.
- Not affiliated with FIFA or ESPN.

## License

**Source-available, free for non-commercial use** under the
[PolyForm Noncommercial License 1.0.0](LICENSE).

You may use, modify, and share Touchline for any non-commercial purpose
(personal use, study, hobby projects, non-profits, schools, government) at no cost.

**Commercial use requires a paid license** — using Touchline or its source for or
within a commercial product, service, or organization. Contact
[@Angryrou](https://github.com/Angryrou) to arrange one.

> Releases v1.0.0 and earlier were published under the MIT License and remain available
> under those terms. This license applies from v1.1.0 onward.
