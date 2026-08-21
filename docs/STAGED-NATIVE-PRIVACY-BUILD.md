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
