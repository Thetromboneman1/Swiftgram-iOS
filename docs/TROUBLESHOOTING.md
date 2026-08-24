# Troubleshooting

Start with the doctor. It reports the actual failing boundary without printing credentials:

```bash
scripts/build-local.sh doctor \
  --signing-dir "$SWIFTGRAM_SIGNING_DIR" \
  --device 00008130-000E65C008E1401C \
  --require-device
```

## Xcode does not match `versions.json`

The repository pins Xcode 26.2. This Mac currently has Xcode 26.6.

- A newer same-major Xcode is treated as a warning and built with `--overrideXcodeVersion`.
- A different major version or an older SDK is a failure.
- Do not edit `versions.json` to silence the check.
- If compilation or linking fails only on 26.6, install 26.2 alongside the current Xcode and select it with `DEVELOPER_DIR` for this build.

The override is acceptable only after simulator, device, and release builds pass.

## 1Password check fails

Use the dedicated helper:

```text
/Users/corn/.local/bin/op-codex
```

The required location is vault `Boneman`, item `Telegram API`, fields `App api_id` and `App api_hash`.

The guarded scripts set `OP_LOAD_DESKTOP_APP_SETTINGS=false` when invoking `op-codex`. This keeps service-account access independent of the desktop app and avoids a CLI 2.35 stall while loading desktop integration settings.

Do not fall back to plain `op` or print the item. If the helper reports a missing vault, grant the Codex service account access to that vault. If it reports a missing field, fix the item metadata instead of hard-coding a value.

## Shell tracing is enabled

The scripts refuse to run when `set -x` or `SHELLOPTS=xtrace` is active. Start a clean shell or run:

```bash
set +x
```

This guard prevents resolved credentials from appearing in terminal or CI logs.

## Provisioning profile is missing or rejected

The full app needs seven explicit profiles. Check the decoded application identifiers in [BUILD.md](BUILD.md).

Common causes:

- Only the wildcard `iOS Team Provisioning Profile: *` exists. It cannot sign the extension set.
- The main profile lacks `aps-environment=development`.
- A profile lacks `group.com.boneman.swiftgram`.
- The target iPhone is not in `ProvisionedDevices`.
- The profile Team ID does not match `B86H3B6X8P`.
- The signing certificate exists but its private key is missing from Keychain.
- More than one profile matches the same bundle identifier in the input directory.
- A personal bundle still requests a managed entitlement such as CarPlay messaging.

Do not disable entitlement validation. Fix the App ID, capability, profile, or bundle configuration.

## Messages appear only after opening the app

First confirm notification permission in iOS Settings, then inspect the signed main-app entitlement and Info.plist in the exact IPA. A development-signed build must have both:

```text
aps-environment = development
TelegramAPSEnvironment = development
```

It must also contain `remote-notification` in `UIBackgroundModes`. Extensions must not carry `aps-environment`.

Telegram's `account.registerDevice` `appSandbox` value must follow `TelegramAPSEnvironment`, not the compiler's Debug or Release mode. An optimized build signed with a development profile still receives a sandbox APNs token. Registering that token as production causes background delivery to fail while foreground synchronization continues to work.

Never print or export the APNs token while diagnosing this path. Runtime evidence may record authorization status, token byte count, selected sandbox/production environment, and redacted registration result only.

## Device is paired but unavailable

Inspect CoreDevice state:

```bash
xcrun devicectl list devices
```

The target is an iPhone 15 Pro on iOS 26.6 with hardware UDID `00008130-000E65C008E1401C`.

A local-network pairing can install and launch while both devices are reachable, but it cannot support a reliable network-disabled translation test because disabling Wi-Fi also drops the developer connection. Connect the iPhone by USB, unlock it, trust the Mac, and leave Developer Mode enabled for the offline test.

## Wrong Bazel target

The application label is:

```text
//Telegram:Swiftgram
```

`//Telegram:Telegram` is not the fork's application target. Use the wrapper instead of calling Bazel directly for signed builds.

## Translation option is missing

- Every Boneman Apple translation mode requires iOS 18 or newer.
- The selected language pair must be supported by Apple.
- Language resources may need a one-time system-managed download.
- Empty, emoji-only, unsupported rich, poll, or audio content is intentionally skipped in strict local-only mode.

Do not add a cloud fallback to make the option appear on unsupported systems.

## Translation waits for a language download

Keep the app in the foreground long enough to accept Apple's system prompt and allow the required language resources to download. The framework owns download consent and progress. After both languages are installed, repeat the translation before starting the offline test.

If the pair remains unavailable, verify it with Apple's `LanguageAvailability` API. Treat an unsupported pair as unsupported, not as a reason to call Telegram or Google.

## Translation unexpectedly reaches a network path

Run the policy check:

```bash
scripts/check-translation-policy.sh
```

Then inspect the caller's backend selection and `localOnly` value. Strict system mode must stop before:

- `messages.translateText`
- Swiftgram's Google wrapper
- poll translation
- rich-message translation
- audio transcription

The repository still contains legacy cloud translation code for upstream compatibility. Its presence is not proof that the Boneman system path uses it. The policy guard and runtime log test must establish the actual path.

## Build output contains a credential

Stop the build immediately. Do not upload or paste the log.

The wrapper streams output through a redactor seeded from the resolved temporary configuration and preserves the build exit code. It removes both generated configuration directories on normal or handled exit. Cleanup is best effort and cannot run after `SIGKILL`, power loss, or a kernel panic. If an unredacted value appears, treat the log as sensitive, fix the redactor or compiler-argument path, and rotate the Telegram API credential if it left the Mac. Then follow the credential-rotation cleanup in [BUILD.md](BUILD.md).

## `xcodebuild archive` fails or creates an incomplete archive

This is expected. The vendored `rules_xcodeproj` documentation says its Archive action is unsupported. Use:

```bash
scripts/build-local.sh release-device --signing-dir "$SWIFTGRAM_SIGNING_DIR"
```

The supported package is the Bazel-generated `Swiftgram.ipa`.

## CI cannot open a synchronization pull request

Check all three conditions:

- The workflow has only the declared `contents: write` and `pull-requests: write` permissions for the sync job.
- Repository Actions settings allow the token to create pull requests.
- The workflow pushes a generated sync branch, not `boneman/main`.

Issues are disabled in this fork. Conflict reporting must stay on the sync pull request or its workflow summary.

## Drift status is YELLOW or RED

- `GREEN`: upstream applies and validation passes.
- `YELLOW`: upstream applies, but exact-candidate validation failed, changed, is pending, or was not confirmed.
- `RED`: Swiftgram history was rewritten or the upstream merge conflicts.

Signing and physical-device failures are local release gates, not drift RED. Never force-push `boneman/main` to clear a RED result. Reproduce the conflict on a separate integration branch and let the sync pull request show the repair.

## Disk use grows unexpectedly

The default Bazel user root and disk cache live under `~/Library/Caches/Swiftgram-Boneman`. Point `--cache-root` at a dedicated location when comparing clean and warm builds. Purge only a dedicated cache root whose `.boneman-swiftgram-cache` is a regular file containing exactly `boneman-swiftgram-cache-v1`. Confirm no build is running first. Do not delete a broad cache or workspace path.

## Memory use grows unexpectedly

`build-local.sh` runs Bazel through a process-group memory guard. The default limits are 12 GiB for one process and 32 GiB for the complete guarded build. An over-limit build exits with status 86 after bounded termination and cleanup.

Check the largest processes before retrying:

```bash
ps -axo pid,ppid,%cpu,rss,etime,command | sort -k4 -nr | head -20
vm_stat
```

Do not run repository-wide code indexing, Gitleaks, Bazel, and Xcode compilation at the same time. Run one large boundary at a time. If a non-build service is growing, stop that exact PID only after confirming its command. Do not use broad `pkill` patterns. Raise the build limits only when the measured compiler workload is legitimate and system memory pressure remains healthy.

# Push registration stalls or messages only arrive after relaunch

If messages catch up only after reopening the app, do not count that as a
successful push test. It proves foreground synchronization, not APNs delivery.

Swiftgram retries transient Telegram `account.registerDevice` failures with a
bounded backoff and reports exhausted failures as failures so iOS can refresh
the APNs token. Redacted device logs contain `Push Registration` start and
completion entries with only the APNs environment, success state, and token
length. They never contain the token itself.

Physical acceptance still requires a new message to display while the phone is
locked and Swiftgram has not been force-quit.
