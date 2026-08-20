# Changelog

All notable Boneman-specific changes are recorded here. Swiftgram and Telegram keep their own upstream history.

## Unreleased

Base references:

- Swiftgram `cf8b23beaaac4126a396337ac2d5be13f9f76b66`
- Telegram comparison `6ad963e5b62d354da79040f388ae2b9132fb17b8`

### Added

- Apple `TranslationSession` translation for individual messages on iOS 18 and newer.
- Lazy whole-chat translation for eligible visible messages.
- Composer translation with an explicit inspect-and-replace step.
- Bounded, deduplicated whole-chat work queue and RAM cache, plus Apple-provenance translated attributes in backup-excluded Postbox.
- Bounded IDs-only ownership tracking so disable, target change, and eviction clear only Boneman Apple attributes.
- Focused policy, cache, normalization, queue, capacity, and cancellation tests.
- Secure 1Password-backed local build, doctor, IPA verification, and artifact scripts.
- A process-group memory guard for local Bazel builds, with bounded termination when a process exceeds the configured limit.
- Unsigned CI, upstream synchronization, Telegram monitoring, drift classification, and conservative Actions Dependabot configuration.
- Build, architecture, translation, privacy, synchronization, release, security, and troubleshooting documentation.

### Changed

- Boneman system translation is local-only and does not fall back to Telegram, Swiftgram's Google wrapper, or another translation API.
- Translation settings expose Apple's backend only where the required iOS 18 API is available.
- Swiftgram updates flow through a clean tracking branch and review PR instead of modifying the maintained branch directly.

### Security

- Integrated selected DNS, drawing, localization-decoder, and animation-cache safety fixes after targeted upstream review.
- Kept Telegram credentials and credential-bearing generated configuration, dedicated Bazel caches, Apple profiles, signing keys, IPA files, and dSYMs out of source control and GitHub Actions.
- Added deep IPA signature, profile, entitlement, bundle, version, and checksum verification to the local release gate.

### Verification

Release status remains pending until the final combined source passes Bazel tests and compilation, the seven-target IPA is signed and verified, the app installs and launches on the iPhone 15 Pro, and translation and offline behavior pass on the physical device.
