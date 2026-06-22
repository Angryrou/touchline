# Security Policy

## Supported versions

Touchline is a small single-binary macOS menu-bar app. Only the latest release
receives fixes. Please run the newest version from
[Releases](https://github.com/Angryrou/touchline/releases/latest).

| Version        | Supported |
| -------------- | --------- |
| Latest release | ✅        |
| Older releases | ❌        |

## What Touchline does (and doesn't) touch

- **Network:** read-only HTTPS requests to ESPN's public scoreboard endpoint
  (`site.api.espn.com`) and image loads from ESPN's CDN. No other hosts.
- **Data:** no account, no login, no analytics, no tracking. The only thing stored
  is local app preferences (`UserDefaults`): your chosen shortcut, starred matches,
  and launch-at-login state.
- **Permissions:** no Accessibility, camera, microphone, contacts, or disk-access
  prompts. The global shortcut uses Carbon hotkeys, which need no special permission.

## Reporting a vulnerability

If you find a security issue, please **do not open a public issue.** Instead:

1. Use GitHub's private vulnerability reporting:
   [Report a vulnerability](https://github.com/Angryrou/touchline/security/advisories/new)
2. Or open a minimal public issue asking the maintainer to contact you, without
   disclosing details.

Please include the version, macOS version, and steps to reproduce. As this is a
hobby project maintained by one person, expect a best-effort response rather than a
guaranteed SLA. Confirmed issues will be fixed in the next release and credited if
you'd like.

## Verifying your download

Releases are distributed as an unsigned, **non-notarized** ad-hoc-signed `.app`
inside a zip. On first launch macOS Gatekeeper will warn; this is expected for
unnotarized apps. If you'd rather not trust the binary, build from source —
everything is a single readable Swift file (`Touchline.swift`) plus `build.sh`.
