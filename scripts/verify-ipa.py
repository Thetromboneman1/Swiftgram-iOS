#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any


EXTENSION_SUFFIXES = (
    ".Share",
    ".NotificationContent",
    ".NotificationService",
    ".SiriIntents",
    ".Widget",
    ".BroadcastUpload",
)

FORBIDDEN_PERSONAL_BUILD_ENTITLEMENTS = {
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


class VerificationError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify a Swiftgram IPA against the Boneman bundle and signing contract."
    )
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--app-version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--minimum-ios", required=True)
    parser.add_argument("--attestation", type=Path, required=True)
    parser.add_argument("--require-development-signing", action="store_true")
    parser.add_argument("--team-id")
    parser.add_argument("--device-udid")
    return parser.parse_args()


def fail(message: str) -> None:
    raise VerificationError(message)


def run(command: list[str], *, stdout: int | None = None) -> subprocess.CompletedProcess[bytes]:
    completed = subprocess.run(
        command,
        check=False,
        stdout=stdout,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        diagnostic = completed.stderr.decode("utf-8", errors="replace").strip()
        fail(f"command failed ({completed.returncode}): {command[0]}: {diagnostic}")
    return completed


def load_plist(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"could not read plist {path}: {error}")
    if not isinstance(value, dict):
        fail(f"plist is not a dictionary: {path}")
    return value


def load_plist_bytes(value: bytes, label: str) -> dict[str, Any]:
    try:
        result = plistlib.loads(value)
    except plistlib.InvalidFileException as error:
        fail(f"could not decode {label}: {error}")
    if not isinstance(result, dict):
        fail(f"decoded {label} is not a dictionary")
    return result


def require_string(mapping: dict[str, Any], key: str, label: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        fail(f"{label} has no valid {key}")
    return value


def validate_zip(ipa_path: Path) -> None:
    try:
        with zipfile.ZipFile(ipa_path) as archive:
            infos = archive.infolist()
            if not infos:
                fail("IPA ZIP is empty")
            for info in infos:
                if "\\" in info.filename:
                    fail(f"IPA contains a non-portable ZIP path: {info.filename!r}")
                path = PurePosixPath(info.filename)
                if path.is_absolute() or ".." in path.parts:
                    fail(f"IPA contains an unsafe ZIP path: {info.filename!r}")
            bad_member = archive.testzip()
            if bad_member is not None:
                fail(f"IPA CRC validation failed at {bad_member!r}")
    except (OSError, zipfile.BadZipFile) as error:
        fail(f"IPA is not a valid ZIP archive: {error}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def decode_profile(profile_path: Path) -> dict[str, Any]:
    completed = run(
        ["/usr/bin/security", "cms", "-D", "-i", str(profile_path)],
        stdout=subprocess.PIPE,
    )
    return load_plist_bytes(completed.stdout, f"profile {profile_path}")


def signed_entitlements(bundle_path: Path) -> dict[str, Any]:
    completed = run(
        ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle_path)],
        stdout=subprocess.PIPE,
    )
    if not completed.stdout:
        fail(f"signed bundle has no entitlements: {bundle_path}")
    return load_plist_bytes(completed.stdout, f"signed entitlements for {bundle_path}")


def signing_certificate_sha1(bundle_path: Path, temporary_directory: Path, index: int) -> str:
    prefix = temporary_directory / f"certificate-{index}-"
    run(
        [
            "/usr/bin/codesign",
            "-d",
            "--extract-certificates",
            str(prefix),
            str(bundle_path),
        ]
    )
    leaf_certificate = Path(f"{prefix}0")
    if not leaf_certificate.is_file():
        fail(f"codesign did not extract a leaf certificate for {bundle_path}")
    return hashlib.sha1(leaf_certificate.read_bytes()).hexdigest().upper()


def validate_signed_bundle(
    *,
    bundle_path: Path,
    expected_bundle_id: str,
    team_id: str,
    device_udid: str,
    required_group: str,
    require_push: bool,
    temporary_directory: Path,
    certificate_index: int,
) -> None:
    run(["/usr/bin/codesign", "--verify", "--strict", "--verbose=2", str(bundle_path)])

    entitlements = signed_entitlements(bundle_path)
    expected_application_identifier = f"{team_id}.{expected_bundle_id}"
    if entitlements.get("application-identifier") != expected_application_identifier:
        fail(f"{expected_bundle_id}: signed application-identifier does not match")
    if entitlements.get("com.apple.developer.team-identifier") != team_id:
        fail(f"{expected_bundle_id}: signed Team ID does not match")
    if entitlements.get("get-task-allow") is not True:
        fail(f"{expected_bundle_id}: output is not development signed")
    signed_groups = entitlements.get("com.apple.security.application-groups", [])
    if signed_groups != [required_group]:
        fail(
            f"{expected_bundle_id}: signed App Groups must be exactly {[required_group]!r}"
        )
    if require_push and entitlements.get("aps-environment") != "development":
        fail(f"{expected_bundle_id}: signed aps-environment is not development")
    if not require_push and "aps-environment" in entitlements:
        fail(f"{expected_bundle_id}: extension must not have aps-environment")

    forbidden = sorted(
        key for key in FORBIDDEN_PERSONAL_BUILD_ENTITLEMENTS if key in entitlements
    )
    if forbidden:
        fail(f"{expected_bundle_id}: forbidden personal-build entitlements: {', '.join(forbidden)}")

    profile_path = bundle_path / "embedded.mobileprovision"
    if not profile_path.is_file():
        fail(f"{expected_bundle_id}: embedded.mobileprovision is missing")
    profile = decode_profile(profile_path)
    profile_entitlements = profile.get("Entitlements", {})
    if not isinstance(profile_entitlements, dict):
        fail(f"{expected_bundle_id}: profile entitlements are invalid")
    if profile_entitlements.get("application-identifier") != expected_application_identifier:
        fail(f"{expected_bundle_id}: profile application-identifier does not match")
    if team_id not in profile.get("TeamIdentifier", []):
        fail(f"{expected_bundle_id}: profile TeamIdentifier does not match")
    if profile_entitlements.get("com.apple.developer.team-identifier") != team_id:
        fail(f"{expected_bundle_id}: profile entitlement Team ID does not match")
    if profile_entitlements.get("get-task-allow") is not True:
        fail(f"{expected_bundle_id}: embedded profile is not for development")
    profile_groups = profile_entitlements.get("com.apple.security.application-groups", [])
    if profile_groups != [required_group]:
        fail(
            f"{expected_bundle_id}: profile App Groups must be exactly {[required_group]!r}"
        )
    if require_push and profile_entitlements.get("aps-environment") != "development":
        fail(f"{expected_bundle_id}: profile aps-environment is not development")
    if not require_push and "aps-environment" in profile_entitlements:
        fail(f"{expected_bundle_id}: extension profile must not have aps-environment")
    if device_udid not in profile.get("ProvisionedDevices", []):
        fail(f"{expected_bundle_id}: target iPhone is absent from the profile")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        fail(f"{expected_bundle_id}: profile expiration is invalid")
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=dt.timezone.utc)
    if expiration <= dt.datetime.now(dt.timezone.utc):
        fail(f"{expected_bundle_id}: embedded profile is expired")

    signer_sha1 = signing_certificate_sha1(
        bundle_path, temporary_directory, certificate_index
    )
    profile_certificate_hashes = {
        hashlib.sha1(certificate).hexdigest().upper()
        for certificate in profile.get("DeveloperCertificates", [])
        if isinstance(certificate, bytes)
    }
    if signer_sha1 not in profile_certificate_hashes:
        fail(f"{expected_bundle_id}: signer certificate is absent from the profile")


def validate_code_objects(app_path: Path) -> None:
    code_objects = {app_path}
    code_objects.update(app_path.rglob("*.appex"))
    code_objects.update(app_path.rglob("*.framework"))
    code_objects.update(app_path.rglob("*.dylib"))
    for code_object in sorted(code_objects, key=lambda value: (len(value.parts), str(value))):
        run(["/usr/bin/codesign", "--verify", "--strict", "--verbose=2", str(code_object)])
    run(
        [
            "/usr/bin/codesign",
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            str(app_path),
        ]
    )


def validate(args: argparse.Namespace) -> dict[str, Any]:
    ipa_path = args.ipa.expanduser().resolve(strict=True)
    if not ipa_path.is_file():
        fail(f"IPA path is not a file: {ipa_path}")
    if args.attestation.exists():
        fail(f"attestation output already exists: {args.attestation}")
    if args.require_development_signing:
        if not args.team_id or not args.device_udid:
            fail("signed verification requires --team-id and --device-udid")

    validate_zip(ipa_path)
    archive_sha256 = sha256_file(ipa_path)

    with tempfile.TemporaryDirectory(prefix="swiftgram-ipa-verify.") as temporary_value:
        temporary_directory = Path(temporary_value)
        extracted_directory = temporary_directory / "extracted"
        extracted_directory.mkdir(mode=0o700)
        run(
            [
                "/usr/bin/ditto",
                "-x",
                "-k",
                str(ipa_path),
                str(extracted_directory),
            ]
        )

        payload = extracted_directory / "Payload"
        app_candidates = sorted(payload.glob("*.app"))
        if len(app_candidates) != 1:
            fail(f"IPA must contain exactly one Payload/*.app, found {len(app_candidates)}")
        app_path = app_candidates[0]
        app_info = load_plist(app_path / "Info.plist")

        actual_bundle_id = require_string(app_info, "CFBundleIdentifier", "main app")
        actual_app_version = require_string(
            app_info, "CFBundleShortVersionString", "main app"
        )
        actual_build_number = require_string(app_info, "CFBundleVersion", "main app")
        actual_minimum_ios = require_string(app_info, "MinimumOSVersion", "main app")

        expected_values = {
            "bundle identifier": (actual_bundle_id, args.bundle_id),
            "app version": (actual_app_version, args.app_version),
            "build number": (actual_build_number, args.build_number),
            "minimum iOS": (actual_minimum_ios, args.minimum_ios),
        }
        for label, (actual, expected) in expected_values.items():
            if actual != expected:
                fail(f"main app {label} is {actual!r}, expected {expected!r}")

        extension_paths: dict[str, Path] = {}
        for extension_path in app_path.rglob("*.appex"):
            info = load_plist(extension_path / "Info.plist")
            extension_bundle_id = require_string(
                info, "CFBundleIdentifier", str(extension_path)
            )
            if extension_bundle_id in extension_paths:
                fail(f"duplicate extension bundle identifier: {extension_bundle_id}")
            extension_paths[extension_bundle_id] = extension_path
            if require_string(info, "CFBundleShortVersionString", extension_bundle_id) != args.app_version:
                fail(f"{extension_bundle_id}: app version does not match the host")
            if require_string(info, "CFBundleVersion", extension_bundle_id) != args.build_number:
                fail(f"{extension_bundle_id}: build number does not match the host")

        expected_extension_ids = {args.bundle_id + suffix for suffix in EXTENSION_SUFFIXES}
        actual_extension_ids = set(extension_paths)
        if actual_extension_ids != expected_extension_ids:
            missing = sorted(expected_extension_ids - actual_extension_ids)
            unexpected = sorted(actual_extension_ids - expected_extension_ids)
            fail(
                "extension set does not match; "
                f"missing={missing or 'none'}, unexpected={unexpected or 'none'}"
            )

        if (app_path / "Watch").exists():
            fail("watch application is present even though this build path disables watch embedding")

        if args.require_development_signing:
            validate_code_objects(app_path)
            assert args.team_id is not None
            assert args.device_udid is not None
            required_group = f"group.{args.bundle_id}"
            signed_bundles = [(args.bundle_id, app_path)] + [
                (bundle_id, extension_paths[bundle_id])
                for bundle_id in sorted(expected_extension_ids)
            ]
            for index, (bundle_id, bundle_path) in enumerate(signed_bundles):
                validate_signed_bundle(
                    bundle_path=bundle_path,
                    expected_bundle_id=bundle_id,
                    team_id=args.team_id,
                    device_udid=args.device_udid,
                    required_group=required_group,
                    require_push=bundle_id == args.bundle_id,
                    temporary_directory=temporary_directory,
                    certificate_index=index,
                )

    return {
        "schema_version": 1,
        "archive_sha256": archive_sha256,
        "bundle_identifier": actual_bundle_id,
        "app_version": actual_app_version,
        "build_number": actual_build_number,
        "minimum_ios_version": actual_minimum_ios,
        "extension_bundle_identifiers": sorted(actual_extension_ids),
        "signing_verified": bool(args.require_development_signing),
        "signing_type": "development" if args.require_development_signing else "not-verified",
    }


def main() -> int:
    args = parse_args()
    try:
        result = validate(args)
        args.attestation.parent.mkdir(parents=True, exist_ok=True)
        with args.attestation.open("x", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2, sort_keys=True)
            handle.write("\n")
    except (OSError, VerificationError) as error:
        print(f"verify-ipa: {error}", file=sys.stderr)
        return 1
    print(
        "verify-ipa: PASS "
        f"({result['bundle_identifier']} {result['app_version']} ({result['build_number']}))"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
