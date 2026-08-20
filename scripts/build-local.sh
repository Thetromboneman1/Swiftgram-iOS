#!/bin/bash

if [[ "$-" == *x* ]] || [[ ":${SHELLOPTS:-}:" == *:xtrace:* ]]; then
    echo "error: shell tracing is enabled; refusing to handle build credentials" >&2
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
template_path="$script_dir/configuration.json.tpl"
verifier_path="$script_dir/verify-ipa.py"
memory_guard_path="$script_dir/run-with-memory-guard.py"

usage() {
    cat <<'EOF'
Usage: scripts/build-local.sh COMMAND [options]

Commands:
  doctor          Validate the host, credentials, profiles, and optional device.
  test            Run a Bazel iOS unit-test target in debug_sim_arm64.
  simulator       Build the full app in debug_sim_arm64.
  debug-device    Build a development-signed debug_arm64 IPA.
  release-device  Build a development-signed release_arm64 IPA and dSYMs.

Options:
  --signing-dir PATH  Private directory containing profiles/*.mobileprovision.
  --bundle-id ID      Bundle ID (default: com.boneman.swiftgram).
  --team-id ID        Apple Team ID (default: B86H3B6X8P).
  --device SELECTOR   CoreDevice ID, hardware UDID, or exact device name.
  --require-device    Require a connected iPhone for the doctor command.
  --host-only         Host-only doctor; skip 1Password and signing checks.
  --build-number N    Positive integer (default: current Unix time).
  --test-target LABEL Bazel test label (default: BonemanTranslationTests).
  --output-dir PATH   Build artifact directory.
  --cache-root PATH   Dedicated Bazel cache root.
  --allow-dirty-release
                      Build an explicitly non-release-eligible preview from a
                      dirty worktree. Clean committed source is the default.
  -h, --help          Show this help.

Environment equivalents:
  SWIFTGRAM_SIGNING_DIR, BONEMAN_BUNDLE_ID, BONEMAN_TEAM_ID,
  SWIFTGRAM_DEVICE, SWIFTGRAM_BUILD_NUMBER, SWIFTGRAM_TEST_TARGET,
  SWIFTGRAM_OUTPUT_DIR, SWIFTGRAM_CACHE_ROOT,
  SWIFTGRAM_ALLOW_DIRTY_RELEASE, SWIFTGRAM_MAX_PROCESS_MIB,
  SWIFTGRAM_MAX_BUILD_GROUP_MIB

The device commands produce Bazel's signed Swiftgram.ipa. They do not use or
claim to support xcodebuild archive. Watch embedding is intentionally disabled.
EOF
}

die() {
    printf 'error: %s\n' "$1" >&2
    exit "${2:-1}"
}

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
command_name="$1"
shift

case "$command_name" in
    doctor|test|simulator|debug-device|release-device)
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        die "unknown command: $command_name" 2
        ;;
esac

user_home="${HOME:?HOME must be set to an absolute user directory}"
bundle_id="${BONEMAN_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
team_id="${BONEMAN_TEAM_ID:-$DEFAULT_TEAM_ID}"
signing_dir="${SWIFTGRAM_SIGNING_DIR:-}"
device_selector="${SWIFTGRAM_DEVICE:-}"
build_number="${SWIFTGRAM_BUILD_NUMBER:-$(date -u +%s)}"
test_target="${SWIFTGRAM_TEST_TARGET:-//Swiftgram/BonemanTranslation:BonemanTranslationTests}"
cache_root="${SWIFTGRAM_CACHE_ROOT:-$user_home/Library/Caches/Swiftgram-Boneman/BazelBuild}"
output_dir="${SWIFTGRAM_OUTPUT_DIR:-}"
allow_dirty_release="${SWIFTGRAM_ALLOW_DIRTY_RELEASE:-0}"
require_device=0
host_only=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --signing-dir)
            [[ $# -ge 2 ]] || die "--signing-dir requires a value" 2
            signing_dir="$2"
            shift 2
            ;;
        --bundle-id)
            [[ $# -ge 2 ]] || die "--bundle-id requires a value" 2
            bundle_id="$2"
            shift 2
            ;;
        --team-id)
            [[ $# -ge 2 ]] || die "--team-id requires a value" 2
            team_id="$2"
            shift 2
            ;;
        --device)
            [[ $# -ge 2 ]] || die "--device requires a value" 2
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
        --build-number)
            [[ $# -ge 2 ]] || die "--build-number requires a value" 2
            build_number="$2"
            shift 2
            ;;
        --test-target)
            [[ $# -ge 2 ]] || die "--test-target requires a value" 2
            test_target="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || die "--output-dir requires a value" 2
            output_dir="$2"
            shift 2
            ;;
        --cache-root)
            [[ $# -ge 2 ]] || die "--cache-root requires a value" 2
            cache_root="$2"
            shift 2
            ;;
        --allow-dirty-release)
            allow_dirty_release=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1" 2
            ;;
    esac
done

if [[ ! "$bundle_id" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || [[ "$bundle_id" != *.* ]]; then
    die "invalid reverse-DNS bundle identifier: $bundle_id" 2
fi
case "$bundle_id" in
    ph.telegra.Telegraph|org.telegram.Telegram-iOS|app.swiftgram.ios)
        die "personal builds must not use an official Telegram or Swiftgram bundle identifier" 2
        ;;
esac
[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || die "Team ID must be exactly ten uppercase letters or digits" 2
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || die "build number must be a positive integer" 2
[[ "$test_target" =~ ^//[^[:space:]]+:[^[:space:]]+$ ]] || die "test target must be a full Bazel label" 2
case "$allow_dirty_release" in
    0|false|FALSE|no|NO|'')
        allow_dirty_release=0
        ;;
    1|true|TRUE|yes|YES)
        allow_dirty_release=1
        ;;
    *)
        die "SWIFTGRAM_ALLOW_DIRTY_RELEASE must be a boolean" 2
        ;;
esac

case "${SWIFTGRAM_EMBED_WATCH_APP:-0}" in
    0|false|FALSE|no|NO|'')
        ;;
    *)
        die "watch embedding is intentionally disabled for this credential-safe build path" 2
        ;;
esac

source_dirty=0
release_head=""
release_status_before=""
if [[ "$command_name" == "release-device" ]]; then
    release_head="$(git -C "$repo_root" rev-parse HEAD)"
    release_status_before="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
    if [[ -n "$release_status_before" ]]; then
        source_dirty=1
        if [[ "$allow_dirty_release" -eq 1 ]]; then
            echo "warning: building a dirty-worktree preview; build-info.json will mark it release_eligible=false" >&2
        else
            die "release-device requires a clean committed worktree; commit the integration or pass --allow-dirty-release for a non-release-eligible preview"
        fi
    fi
elif [[ "$allow_dirty_release" -eq 1 ]]; then
    die "--allow-dirty-release is valid only with release-device" 2
fi

doctor_args=(
    --bundle-id "$bundle_id"
    --team-id "$team_id"
)
if [[ -n "$signing_dir" ]]; then
    doctor_args+=(--signing-dir "$signing_dir")
fi
if [[ -n "$device_selector" ]]; then
    doctor_args+=(--device "$device_selector")
fi
if [[ "$require_device" -eq 1 ]] || [[ "$command_name" == "debug-device" ]] || [[ "$command_name" == "release-device" ]]; then
    doctor_args+=(--require-device)
fi
if [[ "$host_only" -eq 1 ]]; then
    doctor_args+=(--host-only)
fi
if [[ "$command_name" == "test" ]] || [[ "$command_name" == "simulator" ]]; then
    doctor_args+=(--host-only)
fi

if [[ "$command_name" == "doctor" ]]; then
    exec "$script_dir/doctor.sh" "${doctor_args[@]}"
fi

[[ "$host_only" -eq 0 ]] || die "--host-only is valid only with the doctor command" 2
if [[ "$command_name" == "debug-device" ]] || [[ "$command_name" == "release-device" ]]; then
    [[ -n "$signing_dir" ]] || die "--signing-dir or SWIFTGRAM_SIGNING_DIR is required for device builds" 2
fi

"$script_dir/doctor.sh" "${doctor_args[@]}"
if [[ -n "$signing_dir" ]]; then
    signing_dir="$(cd -- "$signing_dir" && pwd -P)"
fi

[[ -f "$verifier_path" ]] || die "missing IPA verifier: $verifier_path"
[[ -f "$memory_guard_path" ]] || die "missing build memory guard: $memory_guard_path"
if [[ "$command_name" == "debug-device" ]] || [[ "$command_name" == "release-device" ]]; then
    [[ -x "$OP_CODEX" ]] || die "required 1Password helper is unavailable: $OP_CODEX"
    [[ -f "$template_path" ]] || die "missing 1Password configuration template: $template_path"
    if ! grep -Fq '{{ op://Boneman/Telegram API/App api_id }}' "$template_path" || ! grep -Fq '{{ op://Boneman/Telegram API/App api_hash }}' "$template_path"; then
        die "configuration template does not contain the two audited 1Password field references"
    fi
fi

if [[ "$cache_root" != /* ]]; then
    cache_root="$repo_root/$cache_root"
fi
case "$cache_root" in
    /|"$repo_root"|"$repo_root"/*|"$user_home")
        die "cache root is too broad: $cache_root" 2
        ;;
esac
if [[ -L "$cache_root" ]]; then
    die "cache root must not be a symlink: $cache_root" 2
fi
if [[ ! -e "$cache_root" ]]; then
    mkdir -p "$cache_root"
elif [[ ! -d "$cache_root" ]]; then
    die "cache root must be a directory: $cache_root" 2
fi
cache_root="$(cd -- "$cache_root" && pwd -P)"
case "$cache_root" in
    /|"$repo_root"|"$repo_root"/*|"$user_home")
        die "resolved cache root is too broad: $cache_root" 2
        ;;
esac
cache_sentinel="$cache_root/.boneman-swiftgram-cache"
if [[ -e "$cache_sentinel" ]] || [[ -L "$cache_sentinel" ]]; then
    [[ -f "$cache_sentinel" ]] && [[ ! -L "$cache_sentinel" ]] \
        || die "cache ownership sentinel must be a regular file: $cache_sentinel" 2
    [[ "$(<"$cache_sentinel")" == "boneman-swiftgram-cache-v1" ]] \
        || die "cache ownership sentinel has unexpected contents: $cache_sentinel" 2
elif find "$cache_root" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    die "refusing to adopt a nonempty cache root without the Boneman ownership sentinel: $cache_root" 2
else
    printf '%s\n' 'boneman-swiftgram-cache-v1' > "$cache_sentinel"
fi
for cache_child in bazel-user-root disk-cache; do
    cache_path="$cache_root/$cache_child"
    if [[ -e "$cache_path" ]] || [[ -L "$cache_path" ]]; then
        [[ -d "$cache_path" ]] && [[ ! -L "$cache_path" ]] \
            || die "Bazel cache path must be a real directory: $cache_path" 2
    else
        mkdir -- "$cache_path"
    fi
done
chmod -R go-rwx "$cache_root/bazel-user-root" "$cache_root/disk-cache"
chmod 600 "$cache_sentinel"
chmod 700 "$cache_root" "$cache_root/bazel-user-root" "$cache_root/disk-cache"
bazel_user_root="$cache_root/bazel-user-root"
disk_cache="$cache_root/disk-cache"

app_version="$(jq -r '.app // empty' "$repo_root/versions.json")"
[[ "$app_version" =~ ^[0-9]+([.][0-9]+)*$ ]] || die "versions.json contains an invalid app version" 2
minimum_ios="$(awk -F'"' '/^minimum_os_version = "/ { print $2; exit }' "$repo_root/Telegram/BUILD")"
[[ "$minimum_ios" =~ ^[0-9]+([.][0-9]+)*$ ]] || die "could not resolve the minimum iOS version from Telegram/BUILD" 2

if [[ -z "$output_dir" ]]; then
    if [[ "$command_name" == "release-device" ]]; then
        output_dir="$repo_root/artifacts"
    else
        output_dir="$repo_root/artifacts/local/${command_name}-${build_number}"
    fi
elif [[ "$output_dir" != /* ]]; then
    output_dir="$repo_root/$output_dir"
fi
case "$output_dir" in
    /|"$repo_root"|"$user_home")
        die "output directory is too broad: $output_dir" 2
        ;;
esac
if [[ "$command_name" != "test" ]]; then
    if [[ -L "$output_dir" ]]; then
        die "output directory must not be a symlink: $output_dir" 2
    fi
    if [[ ! -e "$output_dir" ]]; then
        mkdir -p "$output_dir"
    elif [[ ! -d "$output_dir" ]]; then
        die "output directory must be a directory: $output_dir" 2
    fi
    output_dir="$(cd -- "$output_dir" && pwd -P)"
    case "$output_dir" in
        /|"$repo_root"|"$user_home")
            die "resolved output directory is too broad: $output_dir" 2
        ;;
    esac
    output_sentinel="$output_dir/.boneman-swiftgram-output"
    if [[ -e "$output_sentinel" ]] || [[ -L "$output_sentinel" ]]; then
        [[ -f "$output_sentinel" ]] && [[ ! -L "$output_sentinel" ]] \
            || die "output ownership sentinel must be a regular file: $output_sentinel" 2
        [[ "$(<"$output_sentinel")" == "boneman-swiftgram-output-v1" ]] \
            || die "output ownership sentinel has unexpected contents: $output_sentinel" 2
    elif find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
        die "refusing to adopt a nonempty output directory without the Boneman ownership sentinel: $output_dir" 2
    else
        printf '%s\n' 'boneman-swiftgram-output-v1' > "$output_sentinel"
    fi
    chmod 600 "$output_sentinel"
    chmod 700 "$output_dir"
fi

release_ipa_name=""
release_dsyms_name=""
final_release_ipa=""
final_release_dsyms=""
final_checksums=""
final_build_info=""
if [[ "$command_name" == "release-device" ]]; then
    release_ipa_name="Swiftgram-Boneman-${app_version}-${build_number}.ipa"
    release_dsyms_name="Swiftgram-Boneman-${app_version}-${build_number}.dSYMs.zip"
    final_release_ipa="$output_dir/$release_ipa_name"
    final_release_dsyms="$output_dir/$release_dsyms_name"
    final_checksums="$output_dir/checksums.txt"
    final_build_info="$output_dir/build-info.json"
    if [[ -e "$final_release_ipa" ]] || [[ -e "$final_release_dsyms" ]] || [[ -e "$final_checksums" ]] || [[ -e "$final_build_info" ]]; then
        die "release output already exists; use a different empty --output-dir"
    fi
elif [[ "$command_name" != "test" ]] && [[ -e "$output_dir/Swiftgram.ipa" ]]; then
    die "output IPA already exists; use a new --output-dir: $output_dir/Swiftgram.ipa"
fi

temp_base="${TMPDIR:-/tmp}"
[[ "$temp_base" == /* ]] || die "TMPDIR must be an absolute directory" 2
temp_base="$(cd -- "${temp_base%/}" && pwd -P)"
secure_temp="$(mktemp -d "$temp_base/swiftgram-build.XXXXXX")"
chmod 700 "$secure_temp"
resolved_config="$secure_temp/configuration.json"
custom_config="$secure_temp/configuration.custom.json"
make_output_dir="$output_dir"
if [[ "$command_name" != "test" ]]; then
    make_output_dir="$secure_temp/make-output"
    mkdir -p "$make_output_dir"
fi
generated_configuration_dir="$repo_root/build-input/configuration-repository"
generated_workdir="$repo_root/build-input/configuration-repository-workdir"
build_started=0
configuration_cleanup_required=0
repo_lock_dir=""
repo_lock_acquired=0
release_staging_dir=""
release_publish_started=0
release_publish_complete=0
published_release_ipa=0
published_release_dsyms=0
published_checksums=0
published_build_info=0

cleanup() {
    local exit_status=$?
    local cleanup_failed=0
    trap - EXIT
    set +e
    if [[ "$configuration_cleanup_required" -eq 1 ]] && [[ "$generated_configuration_dir" == "$repo_root/build-input/configuration-repository" ]] && [[ "$generated_workdir" == "$repo_root/build-input/configuration-repository-workdir" ]]; then
        if ! /bin/rm -rf -- "$generated_configuration_dir" "$generated_workdir"; then
            cleanup_failed=1
        fi
    fi
    if [[ "$build_started" -eq 1 ]] && [[ -x "${bazel_binary:-}" ]] && [[ "$bazel_user_root" == "$cache_root/bazel-user-root" ]]; then
        if ! "$bazel_binary" --output_user_root="$bazel_user_root" shutdown >/dev/null 2>&1; then
            cleanup_failed=1
        fi
    fi
    if [[ "$build_started" -eq 1 ]] && [[ "$bazel_user_root" == "$cache_root/bazel-user-root" ]] && [[ -d "$bazel_user_root" ]] && [[ ! -L "$bazel_user_root" ]]; then
        if ! find "$bazel_user_root" -type f \( -name '*.params' -o -name 'command.log' -o -name 'command.profile.gz' \) -delete; then
            cleanup_failed=1
        fi
    fi
    if [[ -n "$release_staging_dir" ]]; then
        case "$release_staging_dir" in
            "$output_dir"/.swiftgram-release.*)
                if ! /bin/rm -rf -- "$release_staging_dir"; then
                    cleanup_failed=1
                fi
                ;;
            *)
                cleanup_failed=1
                ;;
        esac
    fi
    if [[ "$release_publish_started" -eq 1 ]] && [[ "$release_publish_complete" -eq 0 ]]; then
        if [[ "$published_release_ipa" -eq 1 ]] && ! /bin/rm -f -- "$final_release_ipa"; then cleanup_failed=1; fi
        if [[ "$published_release_dsyms" -eq 1 ]] && ! /bin/rm -f -- "$final_release_dsyms"; then cleanup_failed=1; fi
        if [[ "$published_checksums" -eq 1 ]] && ! /bin/rm -f -- "$final_checksums"; then cleanup_failed=1; fi
        if [[ "$published_build_info" -eq 1 ]] && ! /bin/rm -f -- "$final_build_info"; then cleanup_failed=1; fi
    fi
    case "$secure_temp" in
        "$temp_base"/swiftgram-build.*)
            /bin/rm -rf -- "$secure_temp" || cleanup_failed=1
            ;;
        *)
            cleanup_failed=1
            ;;
    esac
    if [[ "$repo_lock_acquired" -eq 1 ]] && [[ -n "$repo_lock_dir" ]]; then
        if ! /bin/rm -f -- "$repo_lock_dir/owner-pid"; then cleanup_failed=1; fi
        if ! /bin/rmdir -- "$repo_lock_dir"; then cleanup_failed=1; fi
    fi
    if [[ "$cleanup_failed" -ne 0 ]]; then
        echo "error: one or more build cleanup operations failed" >&2
        if [[ "$exit_status" -eq 0 ]]; then
            exit_status=1
        fi
    fi
    exit "$exit_status"
}
trap cleanup EXIT

git_common_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)"
repo_lock_dir="$git_common_dir/swiftgram-build.lock"
if ! /bin/mkdir -- "$repo_lock_dir"; then
    lock_owner_pid=""
    if [[ -f "$repo_lock_dir/owner-pid" ]] && [[ ! -L "$repo_lock_dir/owner-pid" ]]; then
        lock_owner_pid="$(<"$repo_lock_dir/owner-pid")"
    fi
    if [[ "$lock_owner_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$lock_owner_pid" 2>/dev/null; then
        die "another live build (PID $lock_owner_pid) owns the repository configuration lock: $repo_lock_dir"
    elif [[ "$lock_owner_pid" =~ ^[1-9][0-9]*$ ]]; then
        /bin/rm -f -- "$repo_lock_dir/owner-pid"
        /bin/rmdir -- "$repo_lock_dir" 2>/dev/null || die "stale build lock could not be recovered safely: $repo_lock_dir"
        /bin/mkdir -- "$repo_lock_dir" || die "another build acquired the repository configuration lock"
    else
        die "repository configuration lock has no verifiable live owner; inspect it manually: $repo_lock_dir"
    fi
fi
repo_lock_acquired=1
printf '%s\n' "$$" > "$repo_lock_dir/owner-pid"

[[ -d "$repo_root/build-input" ]] && [[ ! -L "$repo_root/build-input" ]] \
    || die "build-input must be a real repository directory"
[[ "$(cd -- "$repo_root/build-input" && pwd -P)" == "$repo_root/build-input" ]] \
    || die "build-input resolves outside the repository"
if [[ -L "$generated_configuration_dir" ]]; then
    die "generated configuration directory must not be a symlink: $generated_configuration_dir"
fi
if [[ -d "$generated_configuration_dir" ]]; then
    find "$generated_configuration_dir" -type d -exec chmod 700 {} +
    find "$generated_configuration_dir" -type f -exec chmod 600 {} +
elif [[ -e "$generated_configuration_dir" ]]; then
    die "generated configuration path must be a real directory: $generated_configuration_dir"
fi
if [[ -L "$generated_workdir" ]]; then
    die "generated configuration workdir must not be a symlink: $generated_workdir"
elif [[ -d "$generated_workdir" ]]; then
    find "$generated_workdir" -type d -exec chmod 700 {} +
    find "$generated_workdir" -type f -exec chmod 600 {} +
elif [[ -e "$generated_workdir" ]]; then
    die "generated configuration workdir must be a real directory: $generated_workdir"
fi
/bin/rm -rf -- "$generated_configuration_dir" "$generated_workdir"
configuration_cleanup_required=1

pinned_bazel_version="$(jq -r '.bazel // empty | split(":")[0]' "$repo_root/versions.json")"
[[ "$pinned_bazel_version" =~ ^[0-9]+([.][0-9]+)*$ ]] || die "versions.json contains an invalid Bazel version"
case "$(uname -m)" in
    arm64)
        bazel_platform="darwin-arm64"
        ;;
    x86_64)
        bazel_platform="darwin-x86_64"
        ;;
    *)
        die "unsupported host architecture for the pinned Bazel binary"
        ;;
esac
bazel_binary="$repo_root/build-input/bazel-${pinned_bazel_version}-${bazel_platform}"
if [[ ! -x "$bazel_binary" ]]; then
    if ! (cd "$repo_root" && PYTHONPATH="$repo_root/build-system/Make" python3 -c \
        'import sys; from BazelLocation import locate_bazel; locate_bazel(base_path=sys.argv[1], cache_host_or_path=None, cache_dir=sys.argv[2])' \
        "$repo_root" "$disk_cache"); then
        die "could not download and verify pinned Bazel $pinned_bazel_version"
    fi
fi
[[ -x "$bazel_binary" ]] || die "verified Bazel binary is unavailable: $bazel_binary"

local_bazelrc="$secure_temp/local-only.bazelrc"
bazel_wrapper="$secure_temp/bazel-local-only"
printf '%s\n' \
    'build --remote_cache=' \
    'build --remote_executor=' \
    'build --bes_backend=' \
    'build --experimental_remote_downloader=' \
    'build --remote_upload_local_results=false' \
    'test --remote_cache=' \
    'test --remote_executor=' \
    'test --bes_backend=' \
    'test --experimental_remote_downloader=' \
    'test --remote_upload_local_results=false' \
    > "$local_bazelrc"
chmod 600 "$local_bazelrc"
# The generated wrapper must evaluate its own positional parameters at runtime.
# shellcheck disable=SC2016
printf '#!/bin/bash\nif [[ "${1:-}" == --version ]]; then exec %q --version; fi\nexec %q --bazelrc=%q "$@"\n' \
    "$bazel_binary" "$bazel_binary" "$local_bazelrc" > "$bazel_wrapper"
chmod 700 "$bazel_wrapper"

selected_device_udid=""
if [[ "$command_name" == "debug-device" ]] || [[ "$command_name" == "release-device" ]]; then
    devices_json="$secure_temp/devices.json"
    if ! xcrun devicectl list devices --json-output "$devices_json" >"$secure_temp/devicectl.out" 2>"$secure_temp/devicectl.err"; then
        die "devicectl could not resolve the target iPhone for output verification"
    fi
    available_filter='(.hardwareProperties.reality == "physical") and (.hardwareProperties.platform == "iOS") and (.hardwareProperties.deviceType == "iPhone") and (.connectionProperties.pairingState == "paired") and (.connectionProperties.transportType? != null)'
    if [[ -n "$device_selector" ]]; then
        selected_device_udid="$(jq -r --arg selector "$device_selector" '[.result.devices[] | select('"$available_filter"') | select(.identifier == $selector or .hardwareProperties.udid == $selector or .deviceProperties.name == $selector)] | if length == 1 then .[0].hardwareProperties.udid else empty end' "$devices_json")"
    else
        selected_device_udid="$(jq -r '[.result.devices[] | select('"$available_filter"')] | if length == 1 then .[0].hardwareProperties.udid else empty end' "$devices_json")"
    fi
    [[ -n "$selected_device_udid" ]] || die "target iPhone did not resolve uniquely for output verification"
fi

if [[ "$command_name" == "test" ]] || [[ "$command_name" == "simulator" ]]; then
    if ! jq '
        . + {
            sg_config: "",
            api_id: "10000",
            api_hash: "00000000000000000000000000000000",
            app_center_id: ""
        }
    ' "$repo_root/build-system/appstore-configuration.json" > "$custom_config" 2>"$secure_temp/jq.err"; then
        die "could not prepare the synthetic unsigned-safe build configuration"
    fi
else
    if ! "$OP_CODEX" inject \
        --in-file "$template_path" \
        --out-file "$resolved_config" \
        --file-mode 0600 \
        --force \
        >"$secure_temp/op-inject.out" \
        2>"$secure_temp/op-inject.err"; then
        die "1Password could not resolve Boneman/Telegram API; no secret values were logged"
    fi

    if ! jq --arg bundle_id "$bundle_id" --arg team_id "$team_id" '.bundle_id = $bundle_id | .team_id = $team_id' "$resolved_config" > "$custom_config" 2>"$secure_temp/jq.err"; then
        die "could not prepare the temporary build configuration"
    fi
fi
chmod 600 "$custom_config"
/bin/mv -f -- "$custom_config" "$resolved_config"
chmod 600 "$resolved_config"

if ! jq -e --arg bundle_id "$bundle_id" --arg team_id "$team_id" --arg unsigned_safe "$([[ "$command_name" == "test" || "$command_name" == "simulator" ]] && echo true || echo false)" '
    (($unsigned_safe == "true") or ((.bundle_id == $bundle_id) and (.team_id == $team_id))) and
    (.api_id | type == "string" and test("^[0-9]{4,}$")) and
    (.api_hash | type == "string" and test("^[0-9A-Fa-f]{32}$")) and
    (.app_center_id == "") and
    (($unsigned_safe == "true") or ((.enable_siri == false) and (.enable_icloud == false)))
' "$resolved_config" >/dev/null 2>"$secure_temp/config-validation.err"; then
    die "resolved configuration failed non-secret structural validation"
fi

if grep -Fq 'op://' "$resolved_config"; then
    die "one or more 1Password references were not resolved"
fi

redact_stream() {
    python3 -c 'import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    configuration = json.load(handle)
secrets = [str(configuration.get("api_hash", "")), str(configuration.get("api_id", ""))]
secret_bytes = sorted({value.encode("utf-8") for value in secrets if value}, key=len, reverse=True)
for line in iter(sys.stdin.buffer.readline, b""):
    for secret in secret_bytes:
        line = line.replace(secret, b"<redacted-telegram-api-value>")
    sys.stdout.buffer.write(line)
    sys.stdout.buffer.flush()' "$resolved_config"
}

run_redacted() {
    local -a command_to_run=("$@")
    local -a pipeline_status
    python3 "$memory_guard_path" \
        --max-process-mib "${SWIFTGRAM_MAX_PROCESS_MIB:-12288}" \
        --max-group-mib "${SWIFTGRAM_MAX_BUILD_GROUP_MIB:-32768}" \
        -- "${command_to_run[@]}" 2>&1 | redact_stream
    pipeline_status=("${PIPESTATUS[@]}")
    if [[ "${pipeline_status[1]}" -ne 0 ]]; then
        echo "error: output redaction failed; build status cannot be reported safely" >&2
        return 97
    fi
    return "${pipeline_status[0]}"
}

pinned_xcode="$(jq -r '.xcode' "$repo_root/versions.json")"
actual_xcode="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"

make_args=(
    python3
    build-system/Make/Make.py
    --bazel="$bazel_wrapper"
)
if [[ "$actual_xcode" != "$pinned_xcode" ]]; then
    make_args+=(--overrideXcodeVersion)
fi
make_args+=(
    --bazelUserRoot="$bazel_user_root"
    --cacheDir="$disk_cache"
)

common_operation_args=(
    --configurationPath="$resolved_config"
)
if [[ "$command_name" == "test" ]] || [[ "$command_name" == "simulator" ]]; then
    common_operation_args+=(--codesigningInformationPath="$repo_root/build-system/fake-codesigning")
else
    common_operation_args+=(--codesigningInformationPath="$signing_dir")
fi

case "$command_name" in
    test)
        make_args+=(
            test
            "${common_operation_args[@]}"
            --target="$test_target"
        )
        ;;
    simulator)
        make_args+=(
            build
            "${common_operation_args[@]}"
            --buildNumber="$build_number"
            --configuration=debug_sim_arm64
            --lock
            --outputBuildArtifactsPath="$make_output_dir"
        )
        ;;
    debug-device)
        make_args+=(
            build
            "${common_operation_args[@]}"
            --buildNumber="$build_number"
            --configuration=debug_arm64
            --lock
            --outputBuildArtifactsPath="$make_output_dir"
        )
        ;;
    release-device)
        make_args+=(
            build
            "${common_operation_args[@]}"
            --buildNumber="$build_number"
            --configuration=release_arm64
            --lock
            --outputBuildArtifactsPath="$make_output_dir"
        )
        ;;
esac

echo "build mode: $command_name"
if [[ "$command_name" == "test" ]] || [[ "$command_name" == "simulator" ]]; then
    echo "signing configuration: public fake-signing fixtures with synthetic API values"
else
    echo "bundle identifier: $bundle_id"
    echo "Apple Team ID: $team_id"
fi
echo "Bazel user root: $bazel_user_root"
echo "Bazel disk cache: $disk_cache"
echo "Bazel cache boundary: private local-only cache; remote cache, executor, downloader, and BES are disabled"
echo "watch application: disabled"
if [[ "$command_name" != "test" ]]; then
    echo "artifact directory: $output_dir"
fi

cd "$repo_root"
build_started=1
build_status=0
if run_redacted "${make_args[@]}"; then
    build_status=0
else
    build_status=$?
fi

if [[ "$build_status" -ne 0 ]]; then
    die "Make.py failed for $command_name with exit status $build_status" "$build_status"
fi

if [[ "$command_name" == "test" ]]; then
    echo "success: Bazel test target passed: $test_target"
    exit 0
fi
if [[ "$command_name" == "simulator" ]]; then
    echo "success: full simulator build passed with public fake-signing fixtures"
    exit 0
fi

canonical_ipa="$repo_root/bazel-bin/Telegram/Swiftgram.ipa"
copied_ipa="$make_output_dir/Swiftgram.ipa"
[[ -f "$canonical_ipa" ]] || die "Make.py succeeded but Bazel's canonical IPA is missing: $canonical_ipa"
[[ -f "$copied_ipa" ]] || die "Make.py succeeded but the copied IPA is missing: $copied_ipa"

canonical_sha256="$(shasum -a 256 "$canonical_ipa" | awk '{ print $1 }')"
copied_sha256="$(shasum -a 256 "$copied_ipa" | awk '{ print $1 }')"
[[ "$canonical_sha256" == "$copied_sha256" ]] || die "copied IPA checksum does not match Bazel's canonical IPA"

ipa_attestation="$secure_temp/ipa-attestation.json"
verify_args=(
    python3
    "$verifier_path"
    --ipa "$copied_ipa"
    --bundle-id "$bundle_id"
    --app-version "$app_version"
    --build-number "$build_number"
    --minimum-ios "$minimum_ios"
    --attestation "$ipa_attestation"
)
if [[ "$command_name" == "debug-device" ]] || [[ "$command_name" == "release-device" ]]; then
    verify_args+=(
        --require-development-signing
        --team-id "$team_id"
        --device-udid "$selected_device_udid"
    )
fi
"${verify_args[@]}"
attested_sha256="$(jq -r '.archive_sha256 // empty' "$ipa_attestation")"
[[ "$attested_sha256" == "$canonical_sha256" ]] || die "IPA attestation checksum does not match Bazel's canonical IPA"

if [[ "$command_name" != "release-device" ]]; then
    release_staging_dir="$(mktemp -d "$output_dir/.swiftgram-release.XXXXXX")"
    chmod 700 "$release_staging_dir"
    staged_local_ipa="$release_staging_dir/Swiftgram.ipa"
    final_local_ipa="$output_dir/Swiftgram.ipa"
    /bin/cp -p -- "$copied_ipa" "$staged_local_ipa"
    chmod 600 "$staged_local_ipa"
    [[ ! -e "$final_local_ipa" ]] && [[ ! -L "$final_local_ipa" ]] \
        || die "output IPA appeared during the build; refusing to overwrite it: $final_local_ipa"
    /bin/mv -n -- "$staged_local_ipa" "$final_local_ipa"
    [[ ! -e "$staged_local_ipa" ]] || die "could not publish IPA without overwriting an existing path"
    /bin/rmdir "$release_staging_dir"
    release_staging_dir=""
    if [[ "$command_name" == "debug-device" ]]; then
        echo "success: verified development-signed IPA: $final_local_ipa"
    else
        echo "success: validated simulator IPA: $final_local_ipa"
    fi
    echo "SHA-256: $copied_sha256"
    exit 0
fi

current_head="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$current_head" == "$release_head" ]] || die "HEAD changed during the release build; refusing to package mixed source"
release_status_after="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
[[ "$release_status_after" == "$release_status_before" ]] \
    || die "the worktree changed during the release build; refusing to package mixed source"

swiftgram_base="$(git -C "$repo_root" merge-base "$release_head" refs/remotes/swiftgram/master 2>/dev/null)" || die "could not resolve the Swiftgram base from refs/remotes/swiftgram/master"
telegram_comparison="$(git -C "$repo_root" rev-parse refs/remotes/telegram/master 2>/dev/null)" || die "could not resolve refs/remotes/telegram/master"
xcode_build_version="$(xcodebuild -version | awk 'NR == 2 { print $3 }')"
build_date_utc="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
copied_dsyms="$make_output_dir/Swiftgram.DSYMs.zip"
[[ -f "$copied_dsyms" ]] || die "Make.py succeeded but the release dSYM ZIP is missing: $copied_dsyms"
unzip -tqq "$copied_dsyms" || die "release dSYM ZIP failed integrity validation"
python3 - "$copied_dsyms" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    dwarf_members = [
        entry
        for entry in archive.infolist()
        if not entry.is_dir() and ".dSYM/Contents/Resources/DWARF/" in entry.filename
    ]
if not dwarf_members:
    raise SystemExit("release dSYM ZIP contains no DWARF binary")
PY

release_staging_dir="$(mktemp -d "$output_dir/.swiftgram-release.XXXXXX")"
chmod 700 "$release_staging_dir"
staged_ipa="$release_staging_dir/$release_ipa_name"
staged_dsyms="$release_staging_dir/$release_dsyms_name"
staged_checksums="$release_staging_dir/checksums.txt"
staged_build_info="$release_staging_dir/build-info.json"

/bin/cp -p -- "$copied_ipa" "$staged_ipa"
/bin/cp -p -- "$copied_dsyms" "$staged_dsyms"
chmod 600 "$staged_ipa"
chmod 600 "$staged_dsyms"
staged_sha256="$(shasum -a 256 "$staged_ipa" | awk '{ print $1 }')"
staged_dsyms_sha256="$(shasum -a 256 "$staged_dsyms" | awk '{ print $1 }')"
[[ "$staged_sha256" == "$canonical_sha256" ]] || die "staged release IPA checksum does not match Bazel's canonical IPA"
printf '%s  %s\n' "$staged_sha256" "$release_ipa_name" > "$staged_checksums"
printf '%s  %s\n' "$staged_dsyms_sha256" "$release_dsyms_name" >> "$staged_checksums"
chmod 600 "$staged_checksums"

python3 - \
    "$repo_root" \
    "$swiftgram_base" \
    "$telegram_comparison" \
    "$release_head" \
    "$actual_xcode" \
    "$xcode_build_version" \
    "$build_date_utc" \
    "$ipa_attestation" \
    "$release_ipa_name" \
    "$release_dsyms_name" \
    "$staged_dsyms_sha256" \
    "$source_dirty" \
    "$staged_build_info" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

(
    repo_root,
    swiftgram_base,
    telegram_comparison,
    boneman_commit,
    xcode_version,
    xcode_build_version,
    build_date_utc,
    attestation_path,
    ipa_asset_name,
    dsym_asset_name,
    dsym_sha256,
    source_dirty_raw,
    output_path,
) = sys.argv[1:]

source_dirty = source_dirty_raw == "1"
with open(attestation_path, "r", encoding="utf-8") as handle:
    attestation = json.load(handle)
if attestation.get("signing_verified") is not True:
    raise SystemExit("release IPA signing was not verified")
commit_ids = subprocess.check_output(
    ["git", "-C", repo_root, "rev-list", "--reverse", f"{swiftgram_base}..{boneman_commit}"],
    text=True,
).splitlines()
included_pr_commits = []
for commit_id in commit_ids:
    message = subprocess.check_output(
        ["git", "-C", repo_root, "show", "-s", "--format=%B", commit_id],
        text=True,
    )
    source_matches = re.findall(
        r"\(cherry picked from commit ([0-9a-fA-F]{40})\)",
        message,
    )
    if source_matches:
        included_pr_commits.append(
            {
                "local_commit": commit_id,
                "source_commit": source_matches[-1].lower(),
                "subject": message.splitlines()[0],
            }
        )

metadata = {
    "schema_version": 1,
    "swiftgram_source_commit": swiftgram_base,
    "telegram_upstream_reference": telegram_comparison,
    "boneman_customization_commit": boneman_commit,
    "included_pr_local_commits": included_pr_commits,
    "xcode_version": xcode_version,
    "xcode_build_version": xcode_build_version,
    "build_date_utc": build_date_utc,
    "app_version": attestation["app_version"],
    "build_number": attestation["build_number"],
    "bundle_identifier": attestation["bundle_identifier"],
    "minimum_ios_version": attestation["minimum_ios_version"],
    "extension_bundle_identifiers": attestation["extension_bundle_identifiers"],
    "sha256": attestation["archive_sha256"],
    "ipa_asset": ipa_asset_name,
    "dsym_asset": dsym_asset_name,
    "dsym_sha256": dsym_sha256,
    "signing_status": "verified-development",
    "source_dirty": source_dirty,
    "release_eligible": not source_dirty,
}

path = pathlib.Path(output_path)
with path.open("x", encoding="utf-8") as handle:
    json.dump(metadata, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
chmod 600 "$staged_build_info"

if ! jq -e --arg sha256 "$staged_sha256" --arg dsym_sha256 "$staged_dsyms_sha256" --arg bundle_id "$bundle_id" --arg build_number "$build_number" '
    (.sha256 == $sha256) and
    (.dsym_sha256 == $dsym_sha256) and
    (.bundle_identifier == $bundle_id) and
    (.build_number == $build_number) and
    (.extension_bundle_identifiers | type == "array" and length == 6) and
    (.signing_status == "verified-development") and
    (.included_pr_local_commits | type == "array") and
    (.source_dirty | type == "boolean") and
    (.release_eligible | type == "boolean") and
    (has("api_id") | not) and
    (has("api_hash") | not) and
    (has("device") | not) and
    (has("provisioning_profile") | not) and
    (has("signing_identity") | not)
' "$staged_build_info" >/dev/null; then
    die "generated build-info.json failed non-secret release validation"
fi

release_publish_started=1
for final_path in "$final_release_ipa" "$final_release_dsyms" "$final_checksums" "$final_build_info"; do
    [[ ! -e "$final_path" ]] && [[ ! -L "$final_path" ]] \
        || die "release output appeared during the build; refusing to overwrite it: $final_path"
done
/bin/mv -n -- "$staged_ipa" "$final_release_ipa"
[[ ! -e "$staged_ipa" ]] || die "could not publish release IPA without overwriting an existing path"
published_release_ipa=1
/bin/mv -n -- "$staged_dsyms" "$final_release_dsyms"
[[ ! -e "$staged_dsyms" ]] || die "could not publish release dSYMs without overwriting an existing path"
published_release_dsyms=1
/bin/mv -n -- "$staged_checksums" "$final_checksums"
[[ ! -e "$staged_checksums" ]] || die "could not publish checksums without overwriting an existing path"
published_checksums=1
/bin/mv -n -- "$staged_build_info" "$final_build_info"
[[ ! -e "$staged_build_info" ]] || die "could not publish build metadata without overwriting an existing path"
published_build_info=1
(cd -- "$output_dir" && shasum -a 256 --check "$(basename -- "$final_checksums")") \
    || die "published release artifacts do not match checksums.txt"
release_publish_complete=1
/bin/rmdir "$release_staging_dir"
release_staging_dir=""

echo "success: verified development-signed release IPA: $final_release_ipa"
echo "dSYMs: $final_release_dsyms"
echo "checksums: $final_checksums"
echo "build metadata: $final_build_info"
echo "SHA-256: $staged_sha256"
