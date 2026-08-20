#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

skip_submodules=false
snapshot=false
if [[ "${1:-}" == "--skip-submodules" ]]; then
    skip_submodules=true
elif [[ "${1:-}" == "--snapshot" ]]; then
    skip_submodules=true
    snapshot=true
elif [[ -n "${1:-}" ]]; then
    echo "usage: $0 [--skip-submodules|--snapshot]" >&2
    exit 2
fi

required_paths=(
    .gitleaks.toml
    .gitleaksignore
    .gitmodules
    MODULE.bazel
    WORKSPACE
    versions.json
    build-system/Make/Make.py
    build-system/appstore-configuration.json
    scripts/check-translation-policy.sh
    scripts/public-signing-fixtures.sha256
    scripts/run-with-memory-guard.py
)
for path in "${required_paths[@]}"; do
    [[ -e "${path}" ]] || { echo "repository-policy: missing ${path}" >&2; exit 1; }
done

if [[ "${snapshot}" == false ]]; then
    git diff --check
    committed_base="${CI_COMMITTED_BASE_SHA:-}"
    committed_head="${CI_COMMITTED_HEAD_SHA:-}"
    if [[ -n "${committed_base}" ]]; then
        [[ "${committed_base}" =~ ^[0-9a-fA-F]{40}$ ]] || {
            echo "repository-policy: CI_COMMITTED_BASE_SHA must be a full commit SHA" >&2
            exit 2
        }
        [[ "${committed_head}" =~ ^[0-9a-fA-F]{40}$ ]] || {
            echo "repository-policy: CI_COMMITTED_HEAD_SHA must be a full commit SHA" >&2
            exit 2
        }
        if [[ "${committed_base}" == 0000000000000000000000000000000000000000 ]]; then
            empty_tree="$(git hash-object -t tree /dev/null)"
            git diff --check "${empty_tree}" "${committed_head}"
        else
            git cat-file -e "${committed_base}^{commit}"
            git cat-file -e "${committed_head}^{commit}"
            git diff --check "${committed_base}" "${committed_head}"
        fi
    elif git rev-parse --verify HEAD^1 >/dev/null 2>&1; then
        git diff --check HEAD^1 HEAD
    else
        git show --check --format= HEAD
    fi
    git fsck --connectivity-only --no-dangling
fi

while IFS=' ' read -r _ url; do
    [[ "${url}" == https://* ]] || {
        echo "repository-policy: submodule URL is not HTTPS: ${url}" >&2
        exit 1
    }
done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.url$')

if [[ "${skip_submodules}" == false ]]; then
    submodule_status="$(git submodule status --recursive)"
    if rg --quiet '^[+-U]' <<< "${submodule_status}"; then
        echo "repository-policy: submodule checkout does not match the recorded gitlink" >&2
        rg '^[+-U]' <<< "${submodule_status}" >&2
        exit 1
    fi
fi

if [[ "${snapshot}" == false ]]; then
    PUBLIC_SIGNING_FIXTURE_MANIFEST="${script_dir}/public-signing-fixtures.sha256" python3 - <<'PY'
import os
import re
import subprocess
import hashlib
from pathlib import Path

forbidden = re.compile(
    r"(^|/)(?:"
    r"artifacts/|"
    r"build-input/|"
    r"boneman-configuration\.json$|"
    r"\.env(?:$|\.)|"
    r".*\.ipa$|"
    r".*\.xcarchive(?:/|$)|"
    r".*\.mobileprovision$|"
    r".*\.(?:p8|p12|pfx)$"
    r")",
    re.IGNORECASE,
)
approved_fixture_prefixes = (
    "build-system/example-configuration/provisioning/",
    "build-system/fake-codesigning/",
    "buildbox/fake-codesigning/",
    "third-party/boringssl/src/crypto/pkcs8/test/",
)
signing_suffixes = (".mobileprovision", ".p8", ".p12", ".pfx")
fixture_manifest_path = Path(os.environ["PUBLIC_SIGNING_FIXTURE_MANIFEST"])
fixture_manifest = {}
for line in fixture_manifest_path.read_text(encoding="utf-8").splitlines():
    digest, separator, path = line.partition("  ")
    if not separator or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise SystemExit("repository-policy: malformed public signing fixture manifest")
    if not path.startswith(approved_fixture_prefixes) or not path.lower().endswith(signing_suffixes):
        raise SystemExit(f"repository-policy: unapproved signing fixture manifest path: {path}")
    if path in fixture_manifest:
        raise SystemExit(f"repository-policy: duplicate signing fixture manifest path: {path}")
    fixture_manifest[path] = digest


def is_forbidden(path: str) -> bool:
    if path in fixture_manifest:
        return False
    return forbidden.search(path) is not None


assert not is_forbidden("build-system/fake-codesigning/certs/SelfSigned.p12")
assert not is_forbidden("third-party/boringssl/src/crypto/pkcs8/test/bad1.p12")
assert is_forbidden("private/signing/development.mobileprovision")
assert is_forbidden("nested/private/key.p8")
assert is_forbidden("build-input/configuration-repository/variables.bzl")
assert is_forbidden("artifacts/Swiftgram.ipa")

tracked = subprocess.check_output(["git", "ls-files", "-z"]).decode(
    "utf-8", errors="surrogateescape"
).split("\0")
tracked_set = {path for path in tracked if path}
violations = sorted(path for path in tracked_set if is_forbidden(path))
for path, expected_digest in fixture_manifest.items():
    if path not in tracked_set:
        violations.append(f"{path} (missing public fixture declared by manifest)")
        continue
    actual_digest = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    if actual_digest != expected_digest:
        violations.append(f"{path} (public fixture hash differs from audited manifest)")
if violations:
    raise SystemExit(
        "repository-policy: generated artifact or local secret configuration is tracked:\n"
        + "\n".join(violations)
    )
PY
fi

CI_VALIDATION_SNAPSHOT="${snapshot}" python3 - <<'PY'
import ast
import json
import os
import subprocess
from pathlib import Path

json_paths = [
    Path("versions.json"),
    Path("build-system/appstore-configuration.json"),
    Path("build-system/appcenter-configuration.json"),
    Path("build-system/template_minimal_development_configuration.json"),
]
for path in json_paths:
    with path.open("r", encoding="utf-8") as handle:
        json.load(handle)

versions = json.loads(Path("versions.json").read_text(encoding="utf-8"))
for key in ("app", "xcode", "bazel", "macos"):
    value = versions.get(key)
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"repository-policy: versions.json has invalid {key!r}")

for path in Path("build-system/Make").glob("*.py"):
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))

if os.environ.get("CI_VALIDATION_SNAPSHOT") != "true":
    known_upstream_broken_symlinks = {"AGENTS.md": "swiftgram-scripts/AGENTS.md"}
    for line in subprocess.check_output(["git", "ls-files", "-s"], text=True).splitlines():
        metadata, filename = line.split("\t", 1)
        if metadata.split()[0] != "120000":
            continue
        target = os.readlink(filename)
        if os.path.exists(filename):
            continue
        expected_target = known_upstream_broken_symlinks.get(filename)
        if target != expected_target:
            raise SystemExit(
                f"repository-policy: unexpected broken tracked symlink {filename} -> {target}"
            )
        print(
            "repository-policy: acknowledged upstream broken symlink "
            f"{filename} -> {target}"
        )
PY

if rg --line-number 'pull_request_target|permissions:[[:space:]]*write-all|persist-credentials:[[:space:]]*true|secrets\.' .github/workflows; then
    echo "repository-policy: unsafe GitHub Actions trigger, permission, or secret reference" >&2
    exit 1
fi

python3 - <<'PY'
import re
from pathlib import Path

expected_gitleaks_config = (
    'title = "Swiftgram Boneman secret scanning"\n\n'
    '[extend]\n'
    'useDefault = true\n'
)
if Path(".gitleaks.toml").read_text(encoding="utf-8") != expected_gitleaks_config:
    raise SystemExit("repository-policy: .gitleaks.toml must extend only the default rules")

fingerprints = [
    line
    for line in Path(".gitleaksignore").read_text(encoding="utf-8").splitlines()
    if line and not line.startswith("#")
]
if len(fingerprints) != 1094 or len(set(fingerprints)) != len(fingerprints):
    raise SystemExit("repository-policy: Gitleaks baseline count or uniqueness changed without review")
if any(not re.fullmatch(r"[^:]+:[^:]+:[0-9]+", value) for value in fingerprints):
    raise SystemExit("repository-policy: Gitleaks baseline must contain exact file:rule:line fingerprints")
prefix_counts = {
    prefix: sum(value.startswith(prefix) for value in fingerprints)
    for prefix in ("third-party/", "submodules/", "build-system/")
}
if prefix_counts != {"third-party/": 1077, "submodules/": 11, "build-system/": 6}:
    raise SystemExit("repository-policy: Gitleaks baseline escaped its reviewed upstream path groups")
if any(value.startswith("build-input/") for value in fingerprints):
    raise SystemExit("repository-policy: generated build-input must never be baselined")

unpinned = []
workflow_paths = set(Path(".github/workflows").glob("*.yml"))
workflow_paths.update(Path(".github/workflows").glob("*.yaml"))
for path in sorted(workflow_paths):
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = re.match(r"\s*-?\s*uses:\s*([^\s#]+)", line)
        if not match:
            continue
        action = match.group(1)
        if action.startswith("./") or action.startswith("docker://"):
            continue
        if not re.search(r"@[0-9a-f]{40}$", action):
            unpinned.append(f"{path}:{line_number}: {action}")
if unpinned:
    raise SystemExit("repository-policy: actions must use immutable SHAs:\n" + "\n".join(unpinned))

sync_text = Path(".github/workflows/sync-upstream.yml").read_text(encoding="utf-8")
for required in (
    "CI_SYNC_PHASE: prepare",
    "CI_SYNC_PHASE: finalize",
    "uses: ./.github/workflows/build.yml",
    "validation_commit:",
    "trusted_validator_ref: ${{ needs.prepare.outputs.automation_tip }}",
    "persist-credentials: false",
):
    if required not in sync_text:
        raise SystemExit(f"repository-policy: upstream trust split is missing {required!r}")

build_text = Path(".github/workflows/build.yml").read_text(encoding="utf-8")
for required in (
    "workflow_call:",
    "trusted_validator_ref:",
    "../scripts/ci-validate-repository.sh",
    "--target=//Swiftgram/BonemanTranslation:BonemanTranslationTests",
    "jq '. + {sg_config: \"\"}'",
    "Boneman Translation XCTest execution confirmed",
    "persist-credentials: false",
):
    if required not in build_text:
        raise SystemExit(f"repository-policy: focused read-only validation is missing {required!r}")

build_local_text = Path("scripts/build-local.sh").read_text(encoding="utf-8")
for required in (
    "umask 077",
    "Swiftgram-Boneman/BazelBuild",
    ".boneman-swiftgram-cache",
    ".boneman-swiftgram-output",
    "build --remote_cache=",
    "build --remote_executor=",
    "build --bes_backend=",
    "build --remote_upload_local_results=false",
    "configuration_cleanup_required",
    "'*.params'",
    "run-with-memory-guard.py",
):
    if required not in build_local_text:
        raise SystemExit(f"repository-policy: private local build boundary is missing {required!r}")
PY

"${script_dir}/check-translation-policy.sh"
echo "repository-policy: PASS"
