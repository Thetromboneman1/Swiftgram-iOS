# Release

Source and signed binaries have different exposure rules:

- Source tags and release notes belong in the public fork: `Thetromboneman1/Swiftgram-iOS`.
- A development-signed IPA and matching dSYM ZIP belong in the private release archive: `Thetromboneman1/boneman-dev`.

A development IPA embeds provisioning metadata and compiled Telegram API credentials. A dSYM can expose compiled build details. Publishing either in the public fork would disclose data that is not needed to audit the source. The private archive keeps both available to the account owner without putting them in Git history or a public release.

## Release gate

Do not tag a release until all applicable rows are recorded:

| Gate | Required evidence |
| --- | --- |
| Source | Clean release commit, recursive submodules match, selected upstream commits documented |
| Translation | Focused tests, strict local-only policy check, supported-device interaction test |
| Privacy | No custom translation network fallback, offline test after language download, log review |
| Build | Simulator build, signed Debug device build, signed Release device build |
| Signing | Main app and every embedded extension verify; profiles, Team ID, App Group, and entitlements match |
| Device | Install, launch, and normal Telegram authentication screen reached without handling a login code |
| Security | Redacted secret scan of the custom commit range and final working tree; workflow permissions reviewed |
| Automation | CI, upstream sync, Telegram monitor, and drift result checked at the exact release commit |
| Documentation | README and linked build, translation, privacy, sync, and troubleshooting pages resolve |

An unavailable physical test remains a release blocker. It must not be converted into a pass based on a simulator or static review.

## Build and inspect

Build through the wrapper:

```bash
scripts/build-local.sh release-device \
  --signing-dir "$SWIFTGRAM_SIGNING_DIR" \
  --device 00008130-000E65C008E1401C \
  --build-number "$BUILD_NUMBER"
```

The wrapper creates:

```text
artifacts/Swiftgram-Boneman-<version>-<build>.ipa
artifacts/Swiftgram-Boneman-<version>-<build>.dSYMs.zip
artifacts/checksums.txt
artifacts/build-info.json
```

Extract the IPA without changing its signature:

```bash
install_root="$(mktemp -d "${TMPDIR:-/tmp}/swiftgram-install.XXXXXXXX")"
/usr/bin/ditto -x -k "$IPA_PATH" "$install_root"
app_path="$install_root/Payload/Swiftgram.app"
```

Verify the main app and every embedded code object:

```bash
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
find "$app_path" -type d \( -name '*.appex' -o -name '*.framework' \) -print0 |
  while IFS= read -r -d '' code_path; do
    /usr/bin/codesign --verify --strict --verbose=2 "$code_path"
  done
```

Inspect entitlements without printing private profile contents:

```bash
/usr/bin/codesign -d --entitlements :- "$app_path"
find "$app_path/PlugIns" -maxdepth 1 -name '*.appex' -type d -print0 |
  while IFS= read -r -d '' appex; do
    /usr/bin/codesign -d --entitlements :- "$appex"
  done
```

Confirm the IPA checksum matches both metadata files:

```bash
shasum -a 256 "$IPA_PATH"
cat artifacts/checksums.txt
jq '{app_version, build_number, bundle_identifier, swiftgram_source_commit, telegram_upstream_reference, boneman_customization_commit, sha256, dsym_sha256, signing_status, release_eligible}' artifacts/build-info.json
```

Never paste a decoded provisioning profile or unredacted build command into a release note.

## Install and launch

`devicectl` installs the extracted `.app`, not the IPA ZIP:

```bash
xcrun devicectl device install app \
  --device 00008130-000E65C008E1401C \
  "$app_path" \
  --json-output "$install_root/install.json"

xcrun devicectl device process launch \
  --device 00008130-000E65C008E1401C \
  --terminate-existing \
  com.boneman.swiftgram \
  --json-output "$install_root/launch.json"
```

Use the JSON result to verify installation and launch. Do not parse the human-readable table. Stop at the normal Telegram authentication flow and let the device owner handle any login code.

## Publish

Use a tag such as `boneman-12.9.2-<build>` at the exact tested commit.

Create the public source release without an IPA:

```bash
git tag -a "boneman-12.9.2-${BUILD_NUMBER}" "$RELEASE_COMMIT" \
  -m "Swiftgram Boneman 12.9.2 (${BUILD_NUMBER})"
git push origin "boneman-12.9.2-${BUILD_NUMBER}"
gh release create "boneman-12.9.2-${BUILD_NUMBER}" \
  --repo Thetromboneman1/Swiftgram-iOS \
  --verify-tag \
  --title "Swiftgram Boneman 12.9.2 (${BUILD_NUMBER})" \
  --notes-file "$PUBLIC_RELEASE_NOTES"
```

Create the private binary release and upload only the final inspected files:

```bash
gh release create "boneman-12.9.2-${BUILD_NUMBER}" \
  --repo Thetromboneman1/boneman-dev \
  --target main \
  --title "Swiftgram Boneman 12.9.2 (${BUILD_NUMBER})" \
  --notes-file "$PRIVATE_RELEASE_NOTES" \
  "$IPA_PATH" \
  "$DSYM_PATH" \
  artifacts/checksums.txt \
  artifacts/build-info.json
```

Release notes must include the Swiftgram base, Telegram comparison, Boneman commit, selected PR list, Xcode version, iOS compatibility, bundle identifier, signing scope, translation summary, privacy boundary, and known limitations. They must not include provisioning profiles, secrets, device identifiers, login information, or raw build logs.

## Retention and revocation

- Development IPAs stop installing or launching when their profile expires or is revoked.
- Rebuild after a signing certificate, profile, App Group, device list, or bundle identifier changes.
- Delete the IPA and matching dSYM if a Telegram credential, profile, certificate, device set, or signing input is wrong or rotated.
- Never reuse an artifact whose checksum differs from `build-info.json`.
- Keep source tags immutable. Publish a new build number for any code or signing-input change.
