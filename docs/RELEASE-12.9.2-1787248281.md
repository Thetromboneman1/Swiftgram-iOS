# Release validation record: 12.9.2 (1787248281)

Date: 2026-08-20

This is the validation record for the current Boneman release candidate. Source, build, signing, installation, login, the repaired chat-opening path, and Russian-to-English Apple Translation in direct and group chats have direct physical-device evidence. Offline operation, runtime network observation, and a clean-tip Release repeat remain open release gates. No public source release or private binary release has been published.

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

### Apple whole-chat translation

The first Apple Translation builds opened chats, but whole-chat behavior was incomplete and inconsistent. The translation menu also displayed Cocoon attribution even when Apple was the selected backend. Physical-device diagnostics and repeated Russian-to-English tests isolated a chain of independent defects:

1. Cocoon attribution was unconditional instead of reflecting the selected translation backend.
2. Whole-chat Apple sessions did not prepare an explicit source-to-target language pair for each message.
3. Empty translation attributes left by earlier failures were treated as completed work and suppressed retries.
4. Each persisted result refreshed chat history and replaced the active serial batch subscription, cancelling later messages in the viewport.
5. The `TranslationBatch` coordinator was retained only weakly. Apple produced valid English results, but the coordinator could deallocate before forwarding them to TelegramCore for persistence.
6. Natural Language sometimes classified short Russian Cyrillic slang as Bulgarian or Kazakh, which produced unsupported Apple language-pair failures.
7. A failure for one ambiguous or unsupported message displayed a misleading global language-pack alert even when the installed pair was working.

[PR #4](https://github.com/Thetromboneman1/Swiftgram-iOS/pull/4) fixed the full path and merged as `22379fa8cd65dcec30a303dd1f66b9828e193cc8` after both required checks passed. Apple remains the effective default on iOS 18 and newer. Whole-chat requests remain `localOnly: true` with no Cocoon, Telegram, Google, or other cloud fallback in Apple mode. The app now prepares explicit Apple language pairs, retries stale empty results, permits the bounded serial batch to survive chat refreshes, strongly retains its coordinator through persistence, and uses the chat-level Russian source as a same-script fallback for the observed Bulgarian/Kazakh misclassification. Provider attribution now matches the active backend, and partial failures leave only the affected messages unchanged instead of claiming that a language pack is missing.

The final signed Debug validation build was `12.9.2 (1787259615)`. Its verified IPA SHA-256 is `edcb43376faf26a4947476761c22ab530cf438be16a4159bd2c3857f16184790`. The signed IPA remains private local validation state and is not published in this source repository.

Redacted lifecycle diagnostics recorded only language-pair and result-state metadata, never message text. They showed `ru->en` preparation completing, Apple returning translated result lengths for both long and short messages, and the pre-fix persistence loop repeating. After the strong-retention fix, the loop stopped, the translated content appeared in the chat, and the user confirmed that Russian-to-English translation worked in direct and group chats.

## Evidence

| Gate | Result | Evidence |
| --- | --- | --- |
| Source integrity | Pass for translation fix | Clean `boneman/main` at merge commit `22379fa8cd`; recursive submodules match recorded commits |
| Translation policy | Pass | `scripts/check-translation-policy.sh` |
| Focused translation tests | Pass | `//Swiftgram/BonemanTranslation:BonemanTranslationTests` locally and in CI |
| Pull request protection | Pass | PRs #1, #2, and #4 merged only after both required checks passed |
| Exact-tip CI | Pass | [CI run 32399909450](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32399909450) on `b5d61cc040` |
| Translation-fix CI | Pass | [CI run 32417369756](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32417369756) passed repository policy and focused translation tests before PR #4 merged |
| Upstream automation | Pass | [Upstream Sync 32400475881](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32400475881) published GREEN after exact-commit policy and Translation tests; [Telegram monitor 32400475668](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32400475668) found no pending official Telegram commits |
| Debug device builds | Pass | Signed and verified crash-containment build `1787247741` and translation-fix build `1787259615` |
| Release device build | Pass | Signed and verified build `1787248281`; IPA and dSYM checksums match |
| Signing | Pass | Main app, six extensions, and embedded frameworks pass strict code-signature checks; development profiles, Team ID, App Group, push entitlement, registered device, and private key match |
| Install and launch | Pass | `devicectl` installed and launched Release `1787248281`; process remained alive after the immediate-crash window |
| Login and chat smoke test | Pass on repaired Debug build | Setup and login completed; direct and group chats opened without a crash after the containment fix |
| Apple RU-to-EN chat translation | Pass on fixed Debug build | Build `1787259615`; long and short Russian messages translated in direct and group chats after Apple-managed resource preparation; user confirmed the result |
| Apple backend attribution | Pass | Apple mode identifies Apple on-device Translation and no longer shows Cocoon attribution |
| Failure and retry behavior | Pass for observed RU-to-EN path | Empty stale attributes retry; batches survive history refreshes; persisted results stop the prior repeat loop; isolated ambiguous messages no longer claim a missing pack |
| Offline Translation | Pending | Install both language resources, connect over USB, disable Wi-Fi and cellular data, then repeat translations |
| Runtime privacy observation | Pending | Observe traffic while translating and confirm that no translation request leaves the Apple local path |
| Final clean-tip Release build and physical repeat | Pending | Build the merged documentation tip as Release, verify the artifact and signatures, install it, then repeat chat opening and RU-to-EN translation |

## Publication decision

Publication remains blocked by the pending offline, runtime traffic-observation, and final clean-tip Release rows above. Passing the interactive Apple Translation test does not substitute for the two physical privacy checks or the final Release repeat.

When every row passes:

1. Tag the exact approved source commit in the public fork.
2. Publish source-only notes in `Thetromboneman1/Swiftgram-iOS`.
3. Upload the verified IPA, dSYMs, checksums, and build metadata only to the private `Thetromboneman1/boneman-dev` release.
