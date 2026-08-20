# Security audit

Snapshot: 2026-08-20

This review covers the maintained diff from Swiftgram `cf8b23beaaac4126a396337ac2d5be13f9f76b66`, including selected upstream PRs, Apple translation, local build/signing scripts, GitHub Actions, and release handling.

## Release posture

The source is still pre-release until the final combined diff, signed IPA, embedded profiles, physical-device behavior, and offline translation test pass. A clean compile or successful launch does not close those gates.

## Trust boundaries

| Boundary | Protected asset | Required control |
| --- | --- | --- |
| Telegram messages to translation | Conversation content | `TranslationSession` only; no Telegram or third-party fallback |
| 1Password to build configuration | Telegram API ID and hash | `op-codex`, atomic mode-0600 generated files, redacted logs, and best-effort cleanup on normal or handled exit |
| Keychain and profiles to IPA | Apple private key, device list, entitlements | Local signing only; profiles and keys excluded from Git and Actions |
| Swiftgram upstream to maintained branch | Source integrity | Fast-forward tracking branch plus review PR; no direct production force-push |
| GitHub Actions to repository | Branch and PR integrity | Least privilege; untrusted upstream code must not run with a write token |
| IPA to device and release archive | Executable integrity and signing metadata | Deep signature, profile, entitlement, bundle, version, checksum, install, and launch checks |

## Review results

### Credentials and secrets

- The committed build template contains 1Password references, not secret values.
- The build path uses `/Users/corn/.local/bin/op-codex`; it does not call interactive `op` as a fallback.
- The Telegram API ID and hash become compiler definitions embedded in the app. Resolved credentials are excluded from Git, held in guarded files during the build, redacted from streamed output, and removed from generated Bazel configuration on normal or handled exit.
- Exit cleanup cannot run after `SIGKILL`, power loss, or a kernel panic. Provisioning profiles, certificates, private keys, device identifiers, `.p12`, `.p8`, generated configuration, dedicated Bazel caches, archives, IPA files, and dSYMs are private credential-bearing build state.
- Local Bazel operations run through a process-group memory guard. It terminates only the guarded build group when measured RSS exceeds the configured limit.
- The maintained commit-range scan reported zero findings. The complete staged Boneman changed-surface scan also reported zero findings without a baseline.
- The first full-tree scan reported 1,095 upstream or vendor findings: 1,077 under `third-party`, 11 under `submodules`, 6 under `build-system`, and 1 ignored generated `build-input` path. The generated file was removed. The other 1,094 reviewed file, rule, and line fingerprints are recorded in `.gitleaksignore`; whole vendor directories are not allowlisted. A second full-tree scan against that baseline reported zero new findings.

### Translation networking and storage

- The custom module adds no socket, URL session, HTTP client, telemetry, or third-party translation dependency.
- Apple message translation uses `TranslationSession`, not `translationPresentation`.
- Local-only routing stops before Telegram's translation RPC and Swiftgram's Google wrapper.
- Whole-chat work caching is bounded in RAM. Whole-chat results are also persisted as Apple-provenance `TranslationMessageAttribute` text in backup-excluded Postbox. A bounded IDs-only ownership index enables selective clearing without removing Telegram or Swiftgram translations.
- The physical no-network check is still a separate release gate. See [TRANSLATION-PRIVACY.md](TRANSLATION-PRIVACY.md).

### Entitlements and signing

- The personal bundle uses a unique identifier and a matching private App Group.
- The main app and six active extensions must have explicit matching profiles.
- The main app requires the development Push Notifications entitlement.
- Managed capabilities that are not available to the personal identifier are gated out. They are not replaced with broader entitlements or disabled validation.
- The final IPA verifier must compare the actual embedded bundle IDs, Team/App ID prefixes, profiles, App Group, registered device, versions, minimum OS, and effective entitlements before generating release metadata.

No profile or signed IPA is approved by this document alone.

### URL schemes, ATS, and dependencies

- The Boneman change does not intentionally add a URL scheme, associated domain, ATS exception, background mode, analytics SDK, translator SDK, package, or submodule.
- Existing Telegram and Swiftgram network and URL surfaces remain upstream code. They are outside the custom translation data path.
- Dependabot is limited to GitHub Actions because Telegram's Bazel and submodule revisions are repository-managed and should not be updated independently.

### GitHub Actions

- Third-party actions use immutable commit SHAs.
- Unsigned CI does not receive Telegram credentials, Apple certificates, or provisioning profiles.
- Normal CI uses read-only repository permissions.
- Sync automation may write only the clean tracking branch and manage its pull request. It must not execute untrusted merged upstream scripts with a write credential.
- A GREEN sync result requires the maintained merge candidate and focused translation tests to pass. A clean merge plus static checks alone is not GREEN.
- No workflow force-pushes `boneman/main` or auto-merges a sync PR.

## Selectively integrated security fixes

The targeted Telegram PR review included five minimal safety fixes:

- DNS packet length validation before copy.
- Drawing image-buffer allocation failure handling.
- Bounds checks for persisted localization decoding.
- Animation cache pointer lifetime repair.
- Animation cache failed-initializer ownership repair.

Their exact source and local commit references are in [PR-AUDIT.md](PR-AUDIT.md). They remain subject to the final build and device regression gates.

## Required final evidence

- Final combined-diff security review with every changed file accounted for.
- Gitleaks and targeted credential-pattern scan of the worktree and history.
- Translation policy checks and focused tests.
- Actionlint, ShellCheck, YAML validation, Python compilation, and repository integrity checks.
- Simulator compilation and signed device Debug/Release builds.
- Extracted IPA ZIP and `codesign --verify --deep --strict` checks.
- Embedded profile and effective entitlement comparison for all seven bundles.
- Physical install, launch, crash-log check, and exact translation interactions.
- USB-connected offline translation test after language-resource installation.
- Runtime logs or traffic observation supporting the no-translation-network claim.

Any missing item stays visible in the release report. It is not converted into a pass by source inspection.
