# Swiftgram Boneman

[![CI](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/workflows/build.yml/badge.svg?branch=boneman%2Fmain)](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/workflows/build.yml)
[![Upstream sync](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/workflows/sync-upstream.yml/badge.svg?branch=boneman%2Fmain)](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/workflows/sync-upstream.yml)

This is Dan's maintained Swiftgram iOS fork. It follows Swiftgram for product behavior, watches official Telegram for security and platform changes, and keeps the Boneman customization on a separate branch.

The main customization is strict Apple on-device translation. Message text on that path is translated with Apple's Translation framework. It does not intentionally fall back to Telegram, Google, Microsoft, OpenAI, DeepL, a Swiftgram service, or another translation API.

This project is unofficial and is not affiliated with Telegram, Swiftgram, or Apple.

## Translation

The fork supports:

- Individual message translation through Telegram's native interaction surfaces.
- Whole-chat translation for eligible visible text on iOS 18 or newer.
- Composer translation with an inspect-and-replace step before anything is sent.
- Automatic source-language detection where Apple's API supports it.
- A locally remembered target-language preference.
- Apple-managed language-resource download prompts and expected offline use after the required resources are installed and the release test confirms it.
- A bounded in-memory queue and cache to avoid repeated work while scrolling. Whole-chat results also use Apple-provenance attributes in Telegram's local, backup-excluded Postbox so the existing message renderer can display them after restart.

The app keeps Telegram's upstream minimum of iOS 13.0. Every Boneman Apple translation mode requires iOS 18 or newer. Unsupported systems do not receive a cloud fallback.

See [TRANSLATION.md](docs/TRANSLATION.md) for behavior and limits, and [TRANSLATION-PRIVACY.md](docs/TRANSLATION-PRIVACY.md) for the reviewed data flow and storage details.

## Upstream model

| Branch or remote | Purpose |
| --- | --- |
| `swiftgram/master` | Primary functional upstream |
| `telegram/master` | Secondary security and platform reference |
| `upstream/swiftgram` | Clean mirror used by automation |
| `boneman/main` | Maintained source and customization branch |
| `release/*` | Short-lived release preparation |

Current audited references:

- Swiftgram: `cf8b23beaaac4126a396337ac2d5be13f9f76b66`
- Telegram: `6ad963e5b62d354da79040f388ae2b9132fb17b8`
- App version: `12.9.2`

Swiftgram updates arrive as pull requests into `boneman/main`. Official Telegram changes are monitored and reviewed selectively. Neither upstream is force-pushed into the customization branch.

See [ARCHITECTURE.md](docs/ARCHITECTURE.md), [UPSTREAM-SYNC.md](docs/UPSTREAM-SYNC.md), and the current [PR audit](docs/PR-AUDIT.md).

## Build and install

The supported release path uses the repository's `Make.py` and Bazel build, not a separate Xcode project or `xcodebuild archive`.

```bash
git clone --recursive https://github.com/Thetromboneman1/Swiftgram-iOS.git
cd Swiftgram-iOS
git switch boneman/main
scripts/doctor.sh --host-only
```

Telegram API credentials are resolved at build time from 1Password vault `Boneman`, item `Telegram API`, through `/Users/corn/.local/bin/op-codex`. They become compiler definitions and are embedded in the app, as required by Telegram's build. Secret values, provisioning profiles, signing keys, dedicated Bazel caches, signed IPA files, and dSYMs are private build and release state. They must not enter this source repository or GitHub Actions. Signed IPA and dSYM assets belong only in the private release archive.

Local device builds use bundle identifier `com.boneman.swiftgram`, Team `B86H3B6X8P`, and explicit profiles for the app and six embedded extensions. Start with [BUILD.md](docs/BUILD.md). Release and device-install checks are in [RELEASE.md](docs/RELEASE.md).

## Releases

No public release has been published yet. Release status stays pending until the signed device build, physical translation checks, and offline test pass. When published, source releases will live in this repository and development-signed IPAs will be kept in the private `Thetromboneman1/boneman-dev` archive because embedded profiles contain registered-device and signing-account metadata.

- [Changelog](CHANGELOG.md)
- [Release process](docs/RELEASE.md)

Do not install an IPA whose SHA-256 does not match its `checksums.txt` and `build-info.json`.

## Maintenance and security

CI is unsigned and does not receive Apple or Telegram credentials. It validates repository integrity, the local-only translation policy, the custom translation module, and automation scripts. Signing and release stay local unless a separate reviewed design justifies moving private material into CI.

Local Bazel operations run through per-process and process-group RSS limits. The guard does not cover unrelated services or repository indexers, which must be monitored separately. Codebase indexing is not part of the supported build path.

Scheduled automation:

- Checks Swiftgram daily and opens an auditable synchronization pull request when it changes.
- Classifies drift as GREEN, YELLOW, or RED without rewriting `boneman/main`.
- Compares official Telegram with Swiftgram and surfaces commits and changed paths matching security, crash, iOS or SDK compatibility, Xcode or Bazel/build, networking, MTProto, notification, media, audio, video, or translation signals. It does not claim to measure performance or battery impact.
- Keeps GitHub Action revisions current through conservative Dependabot updates.

Report a security issue privately. Do not put Telegram credentials, provisioning profiles, login codes, device identifiers, or unredacted build logs in a public issue.

## Documentation

- [Build](docs/BUILD.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Translation](docs/TRANSLATION.md)
- [Translation privacy](docs/TRANSLATION-PRIVACY.md)
- [Upstream synchronization](docs/UPSTREAM-SYNC.md)
- [Pull request audit](docs/PR-AUDIT.md)
- [Release](docs/RELEASE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Security audit](docs/SECURITY-AUDIT.md)
