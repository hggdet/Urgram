# Urgram

Urgram is an unofficial Telegram client for iOS, built from the official
open-source Telegram-iOS code (GPL) with its own identity and an extended
feature set. It is **not** affiliated with or endorsed by Telegram.

- Display name: **Urgram** (أورغرام)
- Bundle ID: `com.hggdet.urgram`
- API credentials: the project owner's own api_id/api_hash from
  my.telegram.org, injected at build time via CI secrets (never committed).

## Features

See [FEATURES.md](FEATURES.md) for the full approved feature list
(34 features: ghost mode, anti-delete/anti-edit, restricted-content saving,
hidden chats, streamer mode, bulk downloads, on-device voice-to-text, and more).

## Building

Built on GitHub Actions (public repo) following Telegram's own compilation
guide: `build-system/Make/Make.py build` with a Urgram configuration and
codesigning data generated from Telegram's `fake-codesigning` templates by
`build-system/urgram/generate_codesigning.py`. The resulting IPA is
unsigned/fake-signed and is meant to be re-signed with your own certificate.

## Credits & licence

- Upstream: [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS)
  by Telegram Messenger LLP — GPL. This fork publishes its code in compliance
  with the licence, as required.
- Urgram identity, icons and feature work: Abdulbasit Khudair (ابو العبد).
