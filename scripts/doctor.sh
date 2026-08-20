#!/bin/bash

if [[ "$-" == *x* ]] || [[ ":${SHELLOPTS:-}:" == *:xtrace:* ]]; then
    echo "error: shell tracing is enabled; refusing to inspect signing or credential metadata" >&2
    exit 2
fi

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly DEFAULT_BUNDLE_ID="com.boneman.swiftgram"
readonly DEFAULT_TEAM_ID="B86H3B6X8P"
readonly OP_CODEX="/Users/corn/.local/bin/op-codex"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"

bundle_id="${BONEMAN_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
team_id="${BONEMAN_TEAM_ID:-$DEFAULT_TEAM_ID}"
signing_dir="${SWIFTGRAM_SIGNING_DIR:-}"
device_selector="${SWIFTGRAM_DEVICE:-}"
minimum_free_gb="${SWIFTGRAM_MIN_FREE_GB:-80}"
require_device=0
host_only=0

usage() {
    cat <<'EOF'
Usage: scripts/doctor.sh [options]

Validate the Mac, repository, 1Password metadata, signing profiles, and an
optional physical iPhone for the Boneman Swiftgram build.

Options:
  --signing-dir PATH  Directory containing profiles/*.mobileprovision.
  --bundle-id ID      App bundle identifier (default: com.boneman.swiftgram).
  --team-id ID        Apple Developer Team ID (default: B86H3B6X8P).
  --device SELECTOR   CoreDevice identifier, hardware UDID, or exact device name.
  --require-device    Require one available physical iPhone.
  --host-only         Check host/repository only; skip 1Password and signing.
  -h, --help          Show this help.

Environment equivalents:
  SWIFTGRAM_SIGNING_DIR, BONEMAN_BUNDLE_ID, BONEMAN_TEAM_ID,
  SWIFTGRAM_DEVICE, SWIFTGRAM_MIN_FREE_GB
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --signing-dir)
            [[ $# -ge 2 ]] || { echo "error: --signing-dir requires a value" >&2; exit 2; }
            signing_dir="$2"
            shift 2
            ;;
        --bundle-id)
            [[ $# -ge 2 ]] || { echo "error: --bundle-id requires a value" >&2; exit 2; }
            bundle_id="$2"
            shift 2
            ;;
        --team-id)
            [[ $# -ge 2 ]] || { echo "error: --team-id requires a value" >&2; exit 2; }
            team_id="$2"
            shift 2
            ;;
        --device)
            [[ $# -ge 2 ]] || { echo "error: --device requires a value" >&2; exit 2; }
            device_selector="$2"
            shift 2
            ;;
        --require-device)
            require_device=1
            shift
            ;;
        --host-only)
            host_only=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

failure_count=0
warning_count=0

ok() {
    printf 'ok: %s\n' "$1"
}

warn() {
    warning_count=$((warning_count + 1))
    printf 'warning: %s\n' "$1" >&2
}

fail() {
    failure_count=$((failure_count + 1))
    printf 'error: %s\n' "$1" >&2
}

require_command() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "$1 is available"
    else
        fail "$1 is required but was not found in PATH"
    fi
}

if [[ ! "$bundle_id" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || [[ "$bundle_id" != *.* ]]; then
    fail "bundle identifier is not a valid reverse-DNS identifier: $bundle_id"
fi
case "$bundle_id" in
    ph.telegra.Telegraph|org.telegram.Telegram-iOS|app.swiftgram.ios)
        fail "personal builds must not use an official Telegram or Swiftgram bundle identifier"
        ;;
esac
if [[ ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    fail "Team ID must be exactly ten uppercase letters or digits"
fi
if [[ ! "$minimum_free_gb" =~ ^[0-9]+$ ]] || [[ "$minimum_free_gb" -lt 1 ]]; then
    fail "SWIFTGRAM_MIN_FREE_GB must be a positive integer"
    minimum_free_gb=80
fi

temp_base="${TMPDIR:-/tmp}"
doctor_temp="$(mktemp -d "${temp_base%/}/swiftgram-doctor.XXXXXX")"
chmod 700 "$doctor_temp"

# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
    local exit_status=$?
    local cleanup_failed=0
    trap - EXIT
    set +e
    case "$doctor_temp" in
        "${temp_base%/}"/swiftgram-doctor.*)
            if ! /bin/rm -rf -- "$doctor_temp"; then
                cleanup_failed=1
            fi
            ;;
        *)
            cleanup_failed=1
            ;;
    esac
    if [[ "$cleanup_failed" -ne 0 ]]; then
        echo "error: doctor temporary-file cleanup failed" >&2
        if [[ "$exit_status" -eq 0 ]]; then
            exit_status=1
        fi
    fi
    exit "$exit_status"
}
trap cleanup EXIT

echo "Swiftgram Boneman doctor"
echo "repository: $repo_root"
echo "bundle: $bundle_id"
echo "team: $team_id"

for command_name in codesign ditto git jq openssl plutil python3 security shasum swift unzip xcodebuild xcode-select xcrun zip; do
    require_command "$command_name"
done

ok "$(git --version)"
ok "$(python3 --version 2>&1)"
ok "$(swift --version 2>&1 | awk 'NR == 1 { print; exit }')"

if [[ "$(uname -s)" == "Darwin" ]]; then
    ok "host operating system is macOS $(sw_vers -productVersion)"
else
    fail "this build must run on macOS"
fi

host_arch="$(uname -m)"
if [[ "$host_arch" == "arm64" ]]; then
    ok "host architecture is arm64"
else
    warn "host architecture is $host_arch; this fork is validated primarily on Apple Silicon"
fi

if [[ -f "$repo_root/versions.json" ]] && command -v jq >/dev/null 2>&1; then
    pinned_xcode="$(jq -r '.xcode // empty' "$repo_root/versions.json")"
    pinned_bazel="$(jq -r '.bazel // empty | split(":")[0]' "$repo_root/versions.json")"
    pinned_macos="$(jq -r '.macos // empty' "$repo_root/versions.json")"
    actual_xcode="$(xcodebuild -version 2>/dev/null | awk 'NR == 1 { print $2 }')"
    actual_macos="$(sw_vers -productVersion)"

    if [[ "${actual_macos%%.*}" == "$pinned_macos" ]]; then
        ok "macOS $actual_macos matches the pinned major version $pinned_macos"
    else
        fail "macOS $actual_macos does not match the pinned major version $pinned_macos"
    fi

    if [[ -z "$actual_xcode" ]]; then
        fail "could not determine the active Xcode version"
    elif [[ "$actual_xcode" == "$pinned_xcode" ]]; then
        ok "Xcode $actual_xcode matches versions.json"
    elif python3 -c 'import re,sys; p=lambda value: tuple(int(piece) for piece in re.findall(r"\d+", value)); actual,pinned=p(sys.argv[1]),p(sys.argv[2]); sys.exit(0 if actual and pinned and actual[0] == pinned[0] and actual >= pinned else 1)' "$actual_xcode" "$pinned_xcode"; then
        warn "Xcode $actual_xcode is newer than pinned $pinned_xcode; build-local.sh will use Make.py --overrideXcodeVersion"
    else
        fail "active Xcode $actual_xcode is not a same-major compatible override for pinned $pinned_xcode"
    fi

    active_developer_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ -d "$active_developer_dir" ]]; then
        ok "active developer directory is $active_developer_dir"
    else
        fail "xcode-select does not point to a valid developer directory"
    fi

    case "$host_arch" in
        arm64)
            bazel_platform="darwin-arm64"
            ;;
        x86_64)
            bazel_platform="darwin-x86_64"
            ;;
        *)
            bazel_platform=""
            ;;
    esac
    bazel_binary="$repo_root/build-input/bazel-${pinned_bazel}-${bazel_platform}"
    if [[ -x "$bazel_binary" ]]; then
        actual_bazel="$($bazel_binary --version 2>/dev/null | awk '{ print $2 }')"
        if [[ "$actual_bazel" == "$pinned_bazel" ]]; then
            ok "pinned Bazel $pinned_bazel is present"
        else
            fail "existing Bazel binary reports $actual_bazel, expected $pinned_bazel"
        fi
    else
        warn "pinned Bazel $pinned_bazel is not downloaded yet; Make.py will fetch and checksum it"
    fi
else
    fail "versions.json is missing or jq is unavailable"
fi

available_kb="$(df -Pk "$repo_root" | awk 'NR == 2 { print $4 }')"
if [[ "$available_kb" =~ ^[0-9]+$ ]]; then
    available_gb=$((available_kb / 1024 / 1024))
    if [[ "$available_gb" -ge "$minimum_free_gb" ]]; then
        ok "${available_gb} GiB is available (minimum ${minimum_free_gb} GiB)"
    else
        fail "only ${available_gb} GiB is available; at least ${minimum_free_gb} GiB is required"
    fi
else
    fail "could not determine available disk space"
fi

if [[ -f "$repo_root/build-system/Make/Make.py" ]] && [[ -f "$repo_root/Telegram/BUILD" ]]; then
    ok "Telegram Bazel build entry points are present"
else
    fail "repository is missing Make.py or Telegram/BUILD"
fi

generated_variables="$repo_root/build-input/configuration-repository/variables.bzl"
if [[ -L "$generated_variables" ]]; then
    fail "generated variables.bzl is a symlink; remove the generated configuration safely"
elif [[ -e "$generated_variables" ]]; then
    variables_mode="$(stat -f '%Lp' "$generated_variables" 2>/dev/null || true)"
    variables_owner="$(stat -f '%u' "$generated_variables" 2>/dev/null || true)"
    if [[ ! -f "$generated_variables" ]] || [[ "$variables_mode" != 600 ]] || [[ "$variables_owner" != "$(id -u)" ]]; then
        fail "stale generated variables.bzl has unsafe type, ownership, or mode; expected an owner-only regular file"
    else
        warn "stale generated variables.bzl exists; build-local.sh will remove it before and after the next handled build"
    fi
fi
if [[ -f "$script_dir/verify-ipa.py" ]]; then
    ok "IPA verifier is present"
else
    fail "scripts/verify-ipa.py is missing"
fi

if submodule_state="$(git -C "$repo_root" submodule status --recursive 2>&1)"; then
    if printf '%s\n' "$submodule_state" | grep -Eq '^[-+U]'; then
        fail "one or more submodules are missing, conflicted, or not at the recorded commit"
    else
        ok "recursive submodules match the recorded commits"
    fi
else
    fail "git could not inspect recursive submodules"
fi

selected_device_udid=""
if command -v xcrun >/dev/null 2>&1; then
    devices_json="$doctor_temp/devices.json"
    if xcrun devicectl list devices --json-output "$devices_json" >"$doctor_temp/devicectl.out" 2>"$doctor_temp/devicectl.err"; then
        available_filter='(.hardwareProperties.reality == "physical") and (.hardwareProperties.platform == "iOS") and (.hardwareProperties.deviceType == "iPhone") and (.connectionProperties.pairingState == "paired") and (.connectionProperties.transportType? != null)'
        available_iphone_count="$(jq '[.result.devices[] | select('"$available_filter"')] | length' "$devices_json")"
        ok "CoreDevice sees $available_iphone_count available paired physical iPhone(s)"

        selected_json="$doctor_temp/selected-device.json"
        if [[ -n "$device_selector" ]]; then
            jq --arg selector "$device_selector" '[.result.devices[] | select('"$available_filter"') | select(.identifier == $selector or .hardwareProperties.udid == $selector or .deviceProperties.name == $selector)] | if length == 1 then .[0] else null end' "$devices_json" > "$selected_json"
        elif [[ "$require_device" -eq 1 ]] && [[ "$available_iphone_count" -eq 1 ]]; then
            jq '[.result.devices[] | select('"$available_filter"')] | .[0]' "$devices_json" > "$selected_json"
        else
            printf 'null\n' > "$selected_json"
        fi

        if [[ -n "$device_selector" ]] || [[ "$require_device" -eq 1 ]]; then
            if jq -e 'type == "object"' "$selected_json" >/dev/null; then
                selected_device_udid="$(jq -r '.hardwareProperties.udid' "$selected_json")"
                selected_device_name="$(jq -r '.deviceProperties.name' "$selected_json")"
                selected_device_model="$(jq -r '.hardwareProperties.marketingName' "$selected_json")"
                selected_device_os="$(jq -r '.deviceProperties.osVersionNumber' "$selected_json")"
                selected_device_developer_mode="$(jq -r '.deviceProperties.developerModeStatus' "$selected_json")"
                ok "selected $selected_device_name ($selected_device_model, iOS $selected_device_os)"
                if [[ "$selected_device_developer_mode" == "enabled" ]]; then
                    ok "Developer Mode is enabled on the selected iPhone"
                else
                    fail "Developer Mode is not enabled on the selected iPhone"
                fi
            elif [[ -n "$device_selector" ]]; then
                fail "device selector did not resolve to exactly one available paired physical iPhone"
            else
                fail "--require-device needs exactly one available iPhone, or an explicit --device selector"
            fi
        fi
    elif [[ "$require_device" -eq 1 ]] || [[ -n "$device_selector" ]]; then
        fail "devicectl could not enumerate physical devices"
    else
        warn "devicectl could not enumerate physical devices"
    fi
fi

if [[ "$host_only" -eq 0 ]]; then
    if [[ -x "$OP_CODEX" ]]; then
        if "$OP_CODEX" item get "Telegram API" --vault "Boneman" --format json 2>"$doctor_temp/op.err" | jq -e '([.fields[] | select(.label == "App api_id")] | length == 1) and ([.fields[] | select(.label == "App api_hash")] | length == 1)' >/dev/null; then
            ok "1Password item Boneman/Telegram API contains App api_id and App api_hash"
        else
            fail "op-codex could not verify the two required Telegram API fields in vault Boneman"
        fi
    else
        fail "required 1Password helper is missing or not executable: $OP_CODEX"
    fi

    if [[ -z "$signing_dir" ]]; then
        fail "a private signing directory is required; pass --signing-dir or set SWIFTGRAM_SIGNING_DIR"
    elif [[ ! -d "$signing_dir" ]]; then
        fail "signing directory does not exist: $signing_dir"
    else
        signing_dir="$(cd -- "$signing_dir" && pwd -P)"
        case "$signing_dir/" in
            "$repo_root/"*)
                fail "signing material must be stored outside the Git worktree"
                ;;
            *)
                ok "signing directory is outside the Git worktree"
                ;;
        esac

        profile_dir="$signing_dir/profiles"
        if [[ ! -d "$profile_dir" ]]; then
            fail "signing directory must contain profiles/*.mobileprovision"
        else
            decoded_dir="$doctor_temp/decoded-profiles"
            mkdir -p "$decoded_dir"
            decoded_count=0
            decode_failures=0
            while IFS= read -r -d '' profile_path; do
                decoded_count=$((decoded_count + 1))
                decoded_path="$decoded_dir/profile-${decoded_count}.plist"
                if ! security cms -D -i "$profile_path" > "$decoded_path" 2>"$doctor_temp/profile-${decoded_count}.err"; then
                    decode_failures=$((decode_failures + 1))
                fi
            done < <(find "$profile_dir" -maxdepth 1 -type f -name '*.mobileprovision' -print0)

            if [[ "$decoded_count" -eq 0 ]]; then
                fail "no .mobileprovision files were found in $profile_dir"
            elif [[ "$decode_failures" -ne 0 ]]; then
                fail "$decode_failures provisioning profile(s) could not be decoded"
            else
                ok "$decoded_count provisioning profile file(s) decoded successfully"
            fi

            identities_path="$doctor_temp/codesigning-identities.txt"
            security find-identity -v -p codesigning > "$identities_path" 2>/dev/null || true

            if python3 - "$decoded_dir" "$identities_path" "$team_id" "$bundle_id" "$selected_device_udid" <<'PY'
import datetime
import hashlib
import pathlib
import plistlib
import re
import sys

decoded_dir = pathlib.Path(sys.argv[1])
identities_path = pathlib.Path(sys.argv[2])
team_id = sys.argv[3]
bundle_id = sys.argv[4]
device_udid = sys.argv[5]

suffixes = [
    "",
    ".Share",
    ".NotificationContent",
    ".NotificationService",
    ".SiriIntents",
    ".Widget",
    ".BroadcastUpload",
]
forbidden_entitlements = {
    "com.apple.developer.applesignin",
    "com.apple.developer.associated-domains",
    "com.apple.developer.background-tasks.continued-processing.gpu",
    "com.apple.developer.carplay-messaging",
    "com.apple.developer.icloud-container-identifiers",
    "com.apple.developer.icloud-services",
    "com.apple.developer.in-app-payments",
    "com.apple.developer.pushkit.unrestricted-voip",
    "com.apple.developer.siri",
    "com.apple.developer.ubiquity-kvstore-identifier",
    "com.apple.developer.usernotifications.communication",
    "com.apple.developer.usernotifications.filtering",
}
expected = {bundle_id + suffix for suffix in suffixes}
seen = {}
errors = []
identity_text = identities_path.read_text(encoding="utf-8", errors="replace")
identity_hashes = set(re.findall(r"\b[0-9A-Fa-f]{40}\b", identity_text.upper()))

for path in sorted(decoded_dir.glob("*.plist")):
    try:
        with path.open("rb") as handle:
            profile = plistlib.load(handle)
    except Exception:
        continue

    entitlements = profile.get("Entitlements", {})
    application_identifier = entitlements.get("application-identifier", "")
    prefix = team_id + "."
    if not application_identifier.startswith(prefix):
        continue
    profile_bundle_id = application_identifier[len(prefix):]
    if profile_bundle_id not in expected:
        continue
    if profile_bundle_id in seen:
        errors.append(f"duplicate profile for {profile_bundle_id}")
        continue
    seen[profile_bundle_id] = profile

    team_identifiers = profile.get("TeamIdentifier", [])
    if team_id not in team_identifiers:
        errors.append(f"{profile_bundle_id}: TeamIdentifier does not contain {team_id}")
    if entitlements.get("com.apple.developer.team-identifier") != team_id:
        errors.append(f"{profile_bundle_id}: entitlement Team ID does not match {team_id}")

    app_groups = entitlements.get("com.apple.security.application-groups", [])
    required_group = "group." + bundle_id
    if app_groups != [required_group]:
        errors.append(f"{profile_bundle_id}: App Groups must be exactly [{required_group}]")

    if entitlements.get("get-task-allow") is not True:
        errors.append(f"{profile_bundle_id}: profile is not a development profile")

    if profile_bundle_id == bundle_id:
        if entitlements.get("aps-environment") != "development":
            errors.append(f"{profile_bundle_id}: base profile aps-environment is not development")
    elif "aps-environment" in entitlements:
        errors.append(f"{profile_bundle_id}: extension profile must not have aps-environment")

    forbidden = sorted(forbidden_entitlements.intersection(entitlements))
    if forbidden:
        errors.append(
            f"{profile_bundle_id}: forbidden personal-build entitlements: {', '.join(forbidden)}"
        )

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime.datetime):
        errors.append(f"{profile_bundle_id}: profile has no valid expiration date")
    else:
        now = datetime.datetime.now(datetime.timezone.utc)
        if expiration.tzinfo is None:
            expiration = expiration.replace(tzinfo=datetime.timezone.utc)
        if expiration <= now:
            errors.append(f"{profile_bundle_id}: profile is expired")

    if device_udid and device_udid not in profile.get("ProvisionedDevices", []):
        errors.append(f"{profile_bundle_id}: selected iPhone is absent from ProvisionedDevices")

    certificate_hashes = {
        hashlib.sha1(certificate).hexdigest().upper()
        for certificate in profile.get("DeveloperCertificates", [])
        if isinstance(certificate, bytes)
    }
    if not certificate_hashes.intersection(identity_hashes):
        errors.append(f"{profile_bundle_id}: no matching signing certificate/private key is installed")

missing = sorted(expected.difference(seen))
for profile_bundle_id in missing:
    errors.append(f"missing profile for {profile_bundle_id}")

if errors:
    for error in sorted(errors):
        print(f"profile error: {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"profile set: validated {len(expected)} development profiles")
PY
            then
                ok "development profiles, entitlements, device membership, and installed private key match"
            else
                fail "the signing profile set is not ready for this build"
            fi
        fi
    fi
else
    warn "host-only mode skipped 1Password and signing validation"
fi

if [[ "$failure_count" -eq 0 ]]; then
    echo "ready: all required checks passed with $warning_count warning(s)"
    exit 0
fi

echo "not ready: $failure_count check(s) failed and $warning_count warning(s) were reported" >&2
exit 1
