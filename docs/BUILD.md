# Build

The supported release path is `Make.py` plus Bazel. `scripts/build-local.sh` wraps that path, resolves Telegram API credentials through 1Password, redacts them from build output, and packages local artifacts. It does not use `xcodebuild archive`.

## Current Mac baseline

| Item | Audited value |
| --- | --- |
| macOS | 26.6.2 (25G83) |
| Architecture | Apple Silicon, arm64 |
| Xcode | 26.6 (17F113) |
| Active developer directory | `/Applications/Xcode.app/Contents/Developer` |
| iOS SDK | 26.5 |
| Swift | 6.3.3 |
| Python | 3.14.6 |
| Git | 2.55.0 |
| Bazel | Repository-pinned 8.4.2, downloaded and checksum-verified by `Make.py` |
| Free space at audit | 853 GiB |

`versions.json` pins Xcode 26.2. The doctor reports the local 26.6 installation as a newer same-major override, and the build wrapper passes `--overrideXcodeVersion`. That override is accepted only after the full build passes. Use Xcode 26.2 when byte-for-byte parity with Swiftgram's tagged build is required.

No Homebrew package was added for this fork during the environment audit. Existing installations of `gh`, `jq`, `actionlint`, `shellcheck`, `yamllint`, and `gitleaks` were reused.

## Prerequisites

- A recursive checkout with all recorded submodules initialized.
- Xcode and its command-line tools selected with `xcode-select`.
- `/Users/corn/.local/bin/op-codex` with access to vault `Boneman` and item `Telegram API`.
- A valid Apple Development identity in the login Keychain.
- An absolute signing directory outside the repository.
- At least 80 GiB free by default. Override the doctor threshold only when the actual Bazel cache and artifact plan justifies it.

Run the host-only checks first:

```bash
scripts/doctor.sh --host-only
```

## Credentials

The committed template contains 1Password references, not secret values:

```text
scripts/configuration.json.tpl
```

The build wrapper uses `/Users/corn/.local/bin/op-codex inject` to resolve these verified item fields:

- `App api_id`
- `App api_hash`

The API ID and hash become Bazel compiler definitions and are embedded in the app binary, as required by Telegram's build. The resolved JSON is created in a mode-0600 temporary directory. The generated `variables.bzl` is written atomically with mode 0600. The wrapper refuses to run under shell tracing, never prints the resolved file, redacts both values from streamed build output, and removes the full generated configuration directories on normal or handled exit.

Cleanup is best effort. No process can run an exit trap after `SIGKILL`, sudden power loss, or a kernel panic. Treat the dedicated Bazel user root, disk cache, generated configuration directories, archives, signed IPAs, and dSYMs as private credential-bearing build state. Do not call plain `op`, copy the values into shell history, or place resolved configuration outside the guarded path.

## Signing input

Use this private layout:

```text
/absolute/private/swiftgram-signing/
└── profiles/
    ├── Telegram.mobileprovision
    ├── Share.mobileprovision
    ├── NotificationContent.mobileprovision
    ├── NotificationService.mobileprovision
    ├── Intents.mobileprovision
    ├── Widget.mobileprovision
    └── BroadcastUpload.mobileprovision
```

The profile filenames are conventional; the doctor validates decoded Team ID, application identifier, App Group, expiration, registered device, and required entitlements rather than trusting the filename.

| Target | Required application identifier |
| --- | --- |
| Main app | `B86H3B6X8P.com.boneman.swiftgram` |
| Share | `B86H3B6X8P.com.boneman.swiftgram.Share` |
| Notification content | `B86H3B6X8P.com.boneman.swiftgram.NotificationContent` |
| Notification service | `B86H3B6X8P.com.boneman.swiftgram.NotificationService` |
| Siri intents | `B86H3B6X8P.com.boneman.swiftgram.SiriIntents` |
| Widget | `B86H3B6X8P.com.boneman.swiftgram.Widget` |
| Broadcast upload | `B86H3B6X8P.com.boneman.swiftgram.BroadcastUpload` |

Every profile must use Team `B86H3B6X8P`, contain App Group `group.com.boneman.swiftgram`, include the target iPhone for development signing, and match an installed certificate with its private key. The main app profile also needs `aps-environment=development`. Keep exactly one matching profile per bundle identifier in the directory.

Do not commit, upload, or place this directory inside the checkout.

## Commands

Set the signing directory once if preferred:

```bash
export SWIFTGRAM_SIGNING_DIR=/absolute/private/swiftgram-signing
```

Validate the full machine, secrets metadata, profiles, and target phone:

```bash
scripts/build-local.sh doctor \
  --signing-dir "$SWIFTGRAM_SIGNING_DIR" \
  --device 00008130-000E65C008E1401C \
  --require-device
```

Run the focused translation and push-environment tests:

```bash
scripts/build-local.sh test \
  --test-target //Swiftgram/BonemanTranslation:BonemanTranslationTests

scripts/build-local.sh test \
  --test-target //Swiftgram/SGPushEnvironment:SGPushEnvironmentTests
```

Build for the Apple Silicon simulator:

```bash
scripts/build-local.sh simulator \
  --build-number 1
```

Build a signed Debug IPA for the iPhone:

```bash
scripts/build-local.sh debug-device \
  --signing-dir "$SWIFTGRAM_SIGNING_DIR" \
  --device 00008130-000E65C008E1401C \
  --build-number 1
```

Build the release-optimized, development-signed IPA:

```bash
scripts/build-local.sh release-device \
  --signing-dir "$SWIFTGRAM_SIGNING_DIR" \
  --device 00008130-000E65C008E1401C \
  --build-number 1
```

The release command maps to `Make.py build --configuration=release_arm64 --lock`. It is a release-optimized build. Its distribution scope still comes from the supplied profiles. Development profiles produce an IPA that is valid only for registered devices.

Common overrides are available through flags or environment variables:

| Flag | Environment variable |
| --- | --- |
| `--signing-dir` | `SWIFTGRAM_SIGNING_DIR` |
| `--bundle-id` | `BONEMAN_BUNDLE_ID` |
| `--team-id` | `BONEMAN_TEAM_ID` |
| `--device` | `SWIFTGRAM_DEVICE` |
| `--build-number` | `SWIFTGRAM_BUILD_NUMBER` |
| `--test-target` | `SWIFTGRAM_TEST_TARGET` |
| `--output-dir` | `SWIFTGRAM_OUTPUT_DIR` |
| `--cache-root` | `SWIFTGRAM_CACHE_ROOT` |
| Memory guard | `SWIFTGRAM_MAX_PROCESS_MIB`, `SWIFTGRAM_MAX_BUILD_GROUP_MIB` |

The Watch app stays disabled. Its build path passes Telegram API credentials as Bazel arguments and is outside this personal IPA's signing scope.

## Caches and artifacts

The default dedicated cache root is under `~/Library/Caches/Swiftgram-Boneman`. Override it with `--cache-root` when testing a clean cache.

Every wrapped Bazel operation runs in its own process group through `scripts/run-with-memory-guard.py`. The defaults stop a single process above 12 GiB RSS or the complete build group above 32 GiB RSS. The guard sends `SIGTERM`, waits up to ten seconds, then uses `SIGKILL` only for that build process group. Adjust these limits only when measured builds prove the defaults are too low.

Local outputs use this structure:

```text
artifacts/
├── Swiftgram-Boneman-<version>-<build>.ipa
├── Swiftgram-Boneman-<version>-<build>.dSYMs.zip
├── checksums.txt
└── build-info.json
```

`build-info.json` contains source commits, selected PR references, tool versions, app metadata, and checksums. Its release fields include `app_version`, `build_number`, `bundle_identifier`, `swiftgram_source_commit`, `telegram_upstream_reference`, `boneman_customization_commit`, `sha256`, `dsym_sha256`, `signing_status`, and `release_eligible`. It must not contain credentials, provisioning contents, device identifiers, or signing secrets.

## Clean-checkout validation

Use a fresh worktree or clone at the release commit, then run:

```bash
git submodule update --init --recursive
scripts/doctor.sh --host-only
scripts/build-local.sh test
scripts/build-local.sh simulator
scripts/build-local.sh release-device \
  --signing-dir "$SWIFTGRAM_SIGNING_DIR" \
  --device 00008130-000E65C008E1401C
```

The release is not complete until the IPA and every embedded extension pass signature, entitlement, provisioning-profile, bundle-identifier, and checksum inspection. See [RELEASE.md](RELEASE.md).

## Credential rotation cleanup

If either Telegram API credential is exposed or rotated:

1. Stop the dedicated Bazel server with the repository-pinned binary and the dedicated `--output_user_root`, or let `build-local.sh` finish its shutdown.
2. Remove only `build-input/configuration-repository` and `build-input/configuration-repository-workdir` from this checkout.
3. Purge only the dedicated cache whose root contains `.boneman-swiftgram-cache` with the exact value `boneman-swiftgram-cache-v1`.
4. Remove old private IPA and dSYM assets locally and from the private release archive.
5. Rebuild from a clean checkout with the rotated 1Password values.

Never delete a broad cache, home directory, workspace root, or unsentinelled path.
