# Staged native privacy build

Date: 2026-08-21

This release adds Selective Ghost Mode, typed sponsored-message filtering, bounded local edit history, explicit Files-to-voice conversion, and redacted Apple Translation diagnostics. Simulator staging completed while the device owner was away; the signed release build, installation, and launch completed after the registered iPhone returned.

## Completed before staging

- `//Swiftgram/SGPrivacyTools:SGPrivacyToolsTests` passed.
- `//Swiftgram/BonemanTranslation:BonemanTranslationTests` passed.
- Full `//Telegram:Swiftgram` simulator build `1787330002` passed all 6,147 actions under the repository memory guard after the final settings cleanup.
- Implementation commit `5ed2636fc761bf77dcb1f70fa6fb7f1f01a1b58b` was pushed to `origin/feature/native-privacy-tools`.
- Exact-commit GitHub CI run [32510399409](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32510399409) passed repository and translation policy, workflow and helper validation, secret scanning, and the macOS translation test job.
- No device installation or launch was attempted during unattended staging.

The simulator build uses public fake-signing fixtures and is compiler evidence, not a distributable device artifact.

## Signed release and installation

The registered iPhone later returned through CoreDevice with Developer Mode enabled. The guarded wrapper built the clean committed source tip through `scripts/build-local.sh release-device` as Swiftgram 12.9.2 build `1787335827`.

Release evidence:

- all 6,101 optimized device-build actions completed;
- Telegram API fields, all 7 development provisioning profiles, entitlements, registered-device membership, and the installed private key passed preflight;
- `scripts/verify-ipa.py` passed the IPA structure, nested signatures, profiles, entitlements, device membership, build metadata, and attestation checks;
- IPA SHA-256: `adcf3417cd008b81254d762aa4f380f9a2408d92732afcf319fe13d5d6c63a7f`;
- artifact directory: `artifacts/release-native-privacy-8dd3fb2b49`;
- CoreDevice installed `com.boneman.swiftgram` version 12.9.2 build `1787335827` on device `00008130-000E65C008E1401C`;
- CoreDevice launched the installed app and confirmed its process remained present for the immediate-crash check.

Physical feature behavior still requires the owner-assisted checklist in [NATIVE-PRIVACY-TOOLS.md](NATIVE-PRIVACY-TOOLS.md).

## Whole-chat translation follow-up

Physical testing of build `1787335827` exposed a second Natural Language classification edge case. Russian Cyrillic messages in a long chat were detected as Finnish. The whole-chat caller also discarded the chat's known `ru` source by passing `fromLang: nil`, so Apple correctly rejected the resulting unavailable `fi` to `en` pair and left those messages untranslated.

The follow-up fix centralizes script-safe source resolution in `BonemanTranslationPolicy`, retains a compatible Cyrillic chat source when per-message detection drifts to another script, and forwards the known chat source into the local-only translation request. Regression coverage proves the observed Cyrillic-as-Finnish case resolves to Russian while genuine Finnish Latin text remains Finnish. Focused tests, the translation policy gate, repository validation, and full simulator build `1787337001` passed before the replacement signed-device build.

Screenshots with blank message bodies are separate from translation. Telegram suppresses captured message content in chats with content-saving protection enabled, such as the upstream `Restrict Saving Content` policy. Swiftgram's Privacy Tools do not remove message text from screenshots.

### Mixed-language chat discovery

Physical testing of build `1787338001` found a separate discovery failure in a mostly-English Service X chat containing an Arabic message body. No translation bar or per-message Translate action appeared, and redacted diagnostics remained idle on the prior `ru` to `en` batch. Apple had not received an Arabic request.

The chat detector previously cached the dominant ignored language for an hour and selected it ahead of any smaller foreign-language population. The replacement logic immediately recomputes ignored cached results and prefers the strongest non-ignored language, so an English-plus-Arabic chat exposes Arabic whole-chat translation. Apple mode also offers the eligible per-message Translate action without depending on the legacy cloud-oriented button preference. The path remains Apple `localOnly` with no cloud fallback. Regression tests cover dominant-English/minority-Arabic selection and the all-ignored fallback; full simulator build `1787339001` passed.

## Development-signed Release push repair

Physical testing of optimized build `1787340001` found that messages appeared only after Swiftgram returned to the foreground. The IPA itself was correctly signed with `aps-environment=development`, and the main app contained the `remote-notification` background mode. The failure was downstream of those capabilities: `SharedAccountContext` derived Telegram's `appSandbox` registration flag from `#if DEBUG`. An optimized development-signed build therefore registered its sandbox APNs token as a production token.

The app now embeds the APNs environment resolved from the selected provisioning profile into its main Info.plist and uses that signing-derived value for both Telegram device registration and authorization-code push configuration. Development profiles use APNs sandbox in Debug and Release builds; production profiles continue to use production APNs. A compile-mode fallback remains only for legacy builds without the new metadata. Focused tests cover development, production, normalization, and fallback behavior. APNs token logging now records only token length, never the token value.

### Telegram provider certificate and registration recovery

Further physical testing showed that foreground synchronization could still
hide a failed push path. The final repair treats Telegram device registration
as an observable network operation:

- transient `account.registerDevice` failures use a 15-second request timeout
  and capped backoff instead of being reported as success;
- permanent errors and invalidated tokens reach the existing APNs refresh path;
- completion-only VoIP registration signals are converted into explicit
  completion values so they cannot suppress the APNs result handler; and
- token registration waits until the account network reports `updating` or
  `online`, avoiding requests stranded while the app is backgrounded.

Telegram also requires its own APNs provider certificate for the API
application used by the build. The issued Apple Push Services certificate was
round-tripped through PKCS#12 and exported with `openssl pkcs12 -nodes
-clcerts`, then uploaded to both APNs slots at `my.telegram.org/apps`. The
portal displayed the issued certificate's exact SHA-1 fingerprint in both
slots. Certificate, private key, API hash, and device token remain outside Git.

Physical acceptance completed on 2026-08-24 with Swiftgram 12.9.2 build
`1787520001` from commit `76ba6b55a9`. The optimized signed IPA passed
`verify-ipa`, nested-signature and checksum validation; its SHA-256 is
`98ae84b56af41f092b83858cbae4e37ca0af0d880935859037505d261f7ca14a`.
Exact-commit CI run
[32793506374](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32793506374)
passed. With Swiftgram backgrounded and the phone locked, a scheduled command
to Telegram's verified BotFather produced a normal incoming reply notification
before the app was opened. This is the end-to-end acceptance boundary; seeing
the reply only after foregrounding is not a push pass.

## Reinstall command

After verification, extract the staged IPA into a private temporary directory and install the `.app`, not the IPA ZIP:

```bash
INSTALL_ROOT="$(mktemp -d)"
ditto -x -k "$IPA_PATH" "$INSTALL_ROOT/unpacked"
APP_PATH="$INSTALL_ROOT/unpacked/Payload/Swiftgram.app"
test -x "$APP_PATH/Swiftgram"

xcrun devicectl device install app \
  --device 00008130-000E65C008E1401C \
  "$APP_PATH" \
  --json-output "$INSTALL_ROOT/install.json"

xcrun devicectl device process launch \
  --device 00008130-000E65C008E1401C \
  --terminate-existing \
  com.boneman.swiftgram \
  --json-output "$INSTALL_ROOT/launch.json"
```

Inspect both JSON results. Installation and launch are verified for build `1787335827`; privacy, messaging, and translation behavior remain pending until the physical-device checklist is performed.
