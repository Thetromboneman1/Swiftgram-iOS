# Staged native privacy build

Date: 2026-08-21

This release candidate adds Selective Ghost Mode, typed sponsored-message filtering, bounded local edit history, explicit Files-to-voice conversion, and redacted Apple Translation diagnostics. Implementation and simulator verification can complete while the device owner is away. Installation and physical-device acceptance must wait for the owner to return.

## Completed before staging

- `//Swiftgram/SGPrivacyTools:SGPrivacyToolsTests` passed.
- `//Swiftgram/BonemanTranslation:BonemanTranslationTests` passed.
- Full `//Telegram:Swiftgram` simulator build `1787330002` passed all 6,147 actions under the repository memory guard after the final settings cleanup.
- Implementation commit `5ed2636fc761bf77dcb1f70fa6fb7f1f01a1b58b` was pushed to `origin/feature/native-privacy-tools`.
- Exact-commit GitHub CI run [32510399409](https://github.com/Thetromboneman1/Swiftgram-iOS/actions/runs/32510399409) passed repository and translation policy, workflow and helper validation, secret scanning, and the macOS translation test job.
- No device installation or launch was attempted.

The simulator build uses public fake-signing fixtures and is compiler evidence, not a distributable device artifact.

## Signed artifact gate

The signed release artifact must be produced from the clean committed source tip through `scripts/build-local.sh release-device`. The wrapper requires the private signing directory, 1Password service-account access, and the registered physical iPhone to be available. After the artifact is produced, verify the IPA structure, nested signatures, profiles, entitlements, checksums, and build metadata with the wrapper and `scripts/verify-ipa.py`.

The guarded release preflight validated the Telegram API fields, all 7 development provisioning profiles, entitlements, registered-device membership, and installed private key. It stopped before compilation because device `00008130-000E65C008E1401C` was not available through CoreDevice. Do not substitute another device or bypass this check.

Do not install while the owner is away.

## Install when the owner returns

After verification, extract the staged IPA into a private temporary directory and install the `.app`, not the IPA ZIP:

```bash
INSTALL_ROOT="$(mktemp -d)"
ditto -x -k "$IPA_PATH" "$INSTALL_ROOT/unpacked"
APP_PATH="$INSTALL_ROOT/unpacked/Payload/Telegram.app"
test -x "$APP_PATH/Telegram"

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

Inspect both JSON results. Then perform the physical-device checklist in [NATIVE-PRIVACY-TOOLS.md](NATIVE-PRIVACY-TOOLS.md). Installation, launch, and runtime behavior remain unverified until that checklist is performed.
