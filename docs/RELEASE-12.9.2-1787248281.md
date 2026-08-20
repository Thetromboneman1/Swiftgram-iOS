# Release validation record: 12.9.2 (1787248281)

Date: 2026-08-20

This is the validation record for the current Boneman release candidate. Source, build, signing, installation, login, and the repaired chat-opening path have direct evidence. Apple Translation interaction, offline operation, and runtime network observation remain open release gates. No public source release or private binary release has been published.

## Build identity

| Field | Value |
| --- | --- |
| App version | `12.9.2` |
| Build number | `1787248281` |
| Bundle identifier | `com.boneman.swiftgram` |
| Boneman source commit | `b5d61cc0408dca885cfbc79ffb0d2ee483d23654` |
| Swiftgram source | `cf8b23beaaac4126a396337ac2d5be13f9f76b66` |
| Telegram reference | `6ad963e5b62d354da79040f388ae2b9132fb17b8` |
| Xcode | `26.6` (`17F113`) |
| Minimum iOS | `13.0`; Apple Translation requires iOS 18 or newer |
| Signing | Verified development signing, Team `B86H3B6X8P` |
| IPA SHA-256 | `962e5cc28364b2b37f2f0a06f16a21a4966376998455c298ed27bc63ebcbaad2` |
| dSYM SHA-256 | `c31517028ab51e87b788d31e30e71b5ba7775219587bf4e87681b7668db219bc` |

The private local artifact set is:

- `Swiftgram-Boneman-12.9.2-1787248281.ipa`, 80,411,207 bytes
- `Swiftgram-Boneman-12.9.2-1787248281.dSYMs.zip`, 153,992,458 bytes
- `checksums.txt`
- `build-info.json`

These files are private signing state. They do not belong in the public source repository. The IPA and dSYMs may be uploaded only to the private `Thetromboneman1/boneman-dev` release archive after every remaining release gate passes.

## Changes closed during device validation

### Development signing metadata

[PR #1](https://github.com/Thetromboneman1/Swiftgram-iOS/pull/1) added the effective Team ID entitlement to the main app and updated IPA certificate extraction for the macOS 26.6 `codesign` interface. Both required checks passed before merge commit `675ac55c16c7d668b40be5e79c4f596a1215e45a`.

### Chat-opening crash

The first signed Release build, `1787245325`, installed and completed login, but opening any direct or group chat aborted the process. Six physical-device crash reports reproduced the failure.

The matching Release dSYMs resolved the main-thread stack to:

1. UIKit `_associatedViewControllerForwardsAppearanceCallbacks`
2. `ExperimentalInternalTranslationServiceImpl.Impl.init`
3. `ExperimentalInternalTranslationServiceImpl.init`
4. `ChatControllerImpl.loadDisplayNodeImpl`

The hidden Apple Translation `UIHostingController` was parented to `Window1.viewController`, while its view was inserted directly into the native window root controller's view. iOS 26.6 rejects that cross-controller hierarchy with `SIGABRT`.

[PR #2](https://github.com/Thetromboneman1/Swiftgram-iOS/pull/2) now parents the translation host to the controller that owns the insertion view. The focused signed Debug build `1787247741` installed over the existing bundle, preserved the logged-in data container, and passed direct-chat and group-chat opening on the physical iPhone. No new Swiftgram crash report appeared, and the user confirmed both chat types worked. The fix merged as `b5d61cc0408dca885cfbc79ffb0d2ee483d23654`.

Build `1787245325` is rejected and must not be distributed. Build `1787248281` replaces it.

## Evidence

| Gate | Result | Evidence |
| --- | --- | --- |
| Source integrity | Pass | Clean `boneman/main` at `b5d61cc040`; recursive submodules match recorded commits |
| Translation policy | Pass | `scripts/check-translation-policy.sh` |
| Focused translation tests | Pass | `//Swiftgram/BonemanTranslation:BonemanTranslationTests` locally and in CI |
| Pull request protection | Pass | PRs #1 and #2 merged only after both required checks passed |
| Exact-tip CI | Pass | [CI run 32399909450](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32399909450) on `b5d61cc040` |
| Upstream automation | Pass | [Upstream Sync 32400475881](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32400475881) published GREEN after exact-commit policy and Translation tests; [Telegram monitor 32400475668](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32400475668) found no pending official Telegram commits |
| Debug device build | Pass | Signed and verified build `1787247741` |
| Release device build | Pass | Signed and verified build `1787248281`; IPA and dSYM checksums match |
| Signing | Pass | Main app, six extensions, and embedded frameworks pass strict code-signature checks; development profiles, Team ID, App Group, push entitlement, registered device, and private key match |
| Install and launch | Pass | `devicectl` installed and launched Release `1787248281`; process remained alive after the immediate-crash window |
| Login and chat smoke test | Pass on repaired Debug build | Setup and login completed; direct and group chats opened without a crash after the containment fix |
| Final Release chat repeat | Pending | Repeat direct and group chat opening on installed Release `1787248281` |
| Apple Translation interactions | Pending | English to Spanish, Spanish to English, automatic source detection, download prompt, and repeated-message behavior |
| Offline Translation | Pending | Install both language resources, connect over USB, disable Wi-Fi and cellular data, then repeat translations |
| Runtime privacy observation | Pending | Review logs or traffic during Translation and confirm no Telegram or third-party translation request |

## Publication decision

Publication remains blocked by the three pending Translation rows above. Passing compilation, signing, launch, and the repaired chat smoke test does not substitute for those physical privacy checks.

When every row passes:

1. Tag the exact approved source commit in the public fork.
2. Publish source-only notes in `Thetromboneman1/Swiftgram-iOS`.
3. Upload the verified IPA, dSYMs, checksums, and build metadata only to the private `Thetromboneman1/boneman-dev` release.
