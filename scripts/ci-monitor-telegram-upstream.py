#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


SIGNAL_PATTERN = re.compile(
    r"security|vulnerab|\bcve\b|crash|ios|xcode|\bsdk\b|bazel|build|"
    r"network|mtproto|notification|media|video|audio|translat",
    re.IGNORECASE,
)
PATH_PATTERN = re.compile(
    r"(^|/)(build-system|\.github)(/|$)|"
    r"translation|translate|notification|network|mtproto|media|video|audio|"
    r"(^|/)(BUILD(?:\.bazel)?|[^/]+\.bzl|versions\.json|WORKSPACE(?:\.bazel)?|MODULE\.bazel)$",
    re.IGNORECASE,
)


def run_self_test() -> int:
    expected_matches = (
        "BUILD",
        "Telegram/BUILD",
        "submodules/TelegramCore/BUILD.bazel",
        "build-system/bazel-utils/configuration.bzl",
        "WORKSPACE",
        "MODULE.bazel",
    )
    expected_non_matches = (
        "docs/build-notes.md",
        "submodules/Foo/Sources/Builder.swift",
    )
    for path in expected_matches:
        if not PATH_PATTERN.search(path):
            raise SystemExit(f"telegram-upstream-monitor self-test missed relevant path: {path}")
    for path in expected_non_matches:
        if PATH_PATTERN.search(path):
            raise SystemExit(f"telegram-upstream-monitor self-test overmatched path: {path}")
    print("telegram-upstream-monitor: path self-test PASS")
    return 0


def gh_api(endpoint: str) -> Any:
    completed = subprocess.run(
        ["gh", "api", endpoint],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return json.loads(completed.stdout)


def repository_owner(repository: str) -> str:
    if "/" not in repository:
        raise ValueError(f"invalid GitHub repository: {repository!r}")
    return repository.split("/", 1)[0]


def markdown_escape(value: str) -> str:
    return value.replace("|", "\\|").replace("`", "\\`").replace("\n", " ")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create one aggregate, low-noise Telegram root-upstream comparison report."
    )
    parser.add_argument("--swiftgram-repository", required=True)
    parser.add_argument("--telegram-repository", required=True)
    parser.add_argument("--swiftgram-ref", default="master")
    parser.add_argument("--telegram-ref", default="master")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    telegram_owner = repository_owner(args.telegram_repository)
    compare_endpoint = (
        f"repos/{args.swiftgram_repository}/compare/{args.swiftgram_ref}..."
        f"{telegram_owner}:{args.telegram_ref}"
    )
    comparison = gh_api(compare_endpoint)

    ahead_by = int(comparison.get("ahead_by", 0))
    behind_by = int(comparison.get("behind_by", 0))
    commits = comparison.get("commits", []) if ahead_by > 0 else []
    files = comparison.get("files", []) if ahead_by > 0 else []
    commit_sample_truncated = ahead_by > len(commits)
    file_sample_may_be_truncated = len(files) >= 300

    candidate_commits = []
    for commit in commits:
        message = commit.get("commit", {}).get("message", "").splitlines()[0]
        if SIGNAL_PATTERN.search(message):
            candidate_commits.append(
                {
                    "sha": commit.get("sha", ""),
                    "title": message,
                    "url": commit.get("html_url", ""),
                    "date": commit.get("commit", {}).get("committer", {}).get("date", ""),
                }
            )

    relevant_files = sorted(
        {
            str(item.get("filename", ""))
            for item in files
            if PATH_PATTERN.search(str(item.get("filename", "")))
        }
    )

    telegram_tags = gh_api(f"repos/{args.telegram_repository}/tags?per_page=30")
    swiftgram_tags = gh_api(f"repos/{args.swiftgram_repository}/tags?per_page=30")
    swiftgram_tag_names = {str(item.get("name", "")) for item in swiftgram_tags}
    unseen_tags = [
        {"name": str(item.get("name", "")), "sha": str(item.get("commit", {}).get("sha", ""))}
        for item in telegram_tags
        if str(item.get("name", "")) not in swiftgram_tag_names
    ]

    if (
        unseen_tags
        or candidate_commits
        or relevant_files
        or commit_sample_truncated
        or file_sample_may_be_truncated
    ):
        state = "REVIEW"
    elif ahead_by > 0:
        state = "INFO"
    else:
        state = "CLEAR"

    digest_input = {
        "state": state,
        "ahead_by": ahead_by,
        "behind_by": behind_by,
        "candidate_commits": candidate_commits,
        "relevant_files": relevant_files,
        "unseen_tags": unseen_tags,
        "commit_sample_truncated": commit_sample_truncated,
        "file_sample_may_be_truncated": file_sample_may_be_truncated,
    }
    digest = hashlib.sha256(
        json.dumps(digest_input, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()[:16]

    generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    lines = [
        f"<!-- telegram-monitor-digest:{digest} -->",
        f"# Telegram root-upstream monitor: {state}",
        "",
        f"Generated: `{generated_at}`",
        "",
        "| Comparison | Count |",
        "| --- | ---: |",
        f"| Official Telegram commits not in Swiftgram | {ahead_by} |",
        f"| Swiftgram commits not in official Telegram | {behind_by} |",
        f"| Signal-matching commit titles | {len(candidate_commits)} |",
        f"| Signal-matching changed paths | {len(relevant_files)} |",
        f"| Official release tags absent from Swiftgram | {len(unseen_tags)} |",
        "",
    ]

    if state == "CLEAR":
        lines.append("Swiftgram contains the current official Telegram tip; no root-upstream review is needed.")
    elif state == "INFO":
        lines.append(
            "Official Telegram has commits not yet in Swiftgram, but this bounded keyword/path pass found no high-priority signal."
        )
    else:
        lines.append(
            "Review these aggregate signals selectively. This monitor never merges official Telegram into Swiftgram or opens one issue per commit."
        )

    if commit_sample_truncated or file_sample_may_be_truncated:
        lines.extend(
            [
                "",
                "> GitHub's compare response was truncated. Review the full comparison before classifying the root-upstream delta.",
            ]
        )

    if unseen_tags:
        lines.extend(["", "## New official release tags", ""])
        for tag in unseen_tags[:20]:
            lines.append(f"- `{markdown_escape(tag['name'])}` at `{tag['sha'][:12]}`")

    if candidate_commits:
        lines.extend(["", "## Candidate commits", ""])
        for commit in candidate_commits[:50]:
            title = markdown_escape(commit["title"])
            lines.append(f"- [`{commit['sha'][:12]}`]({commit['url']}) {title}")
        if len(candidate_commits) > 50:
            lines.append(f"- ... {len(candidate_commits) - 50} more candidate commits in the comparison")

    if relevant_files:
        lines.extend(["", "## Relevant changed paths", ""])
        for filename in relevant_files[:50]:
            lines.append(f"- `{markdown_escape(filename)}`")
        if len(relevant_files) > 50:
            lines.append(f"- ... {len(relevant_files) - 50} more signal-matching paths")

    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            "This is a triage signal, not an integration decision. Inspect the official diff, Swiftgram equivalents, CI, privacy, security, performance, and conflict risk before selecting any patch.",
            "",
        ]
    )

    metadata = {
        **digest_input,
        "digest": digest,
        "generated_at": generated_at,
        "swiftgram_repository": args.swiftgram_repository,
        "swiftgram_ref": args.swiftgram_ref,
        "telegram_repository": args.telegram_repository,
        "telegram_ref": args.telegram_ref,
        "compare_url": comparison.get("html_url", ""),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.metadata.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text("\n".join(lines), encoding="utf-8")
    args.metadata.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"telegram-upstream-monitor: {state} ({digest})")
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        raise SystemExit(run_self_test())
    raise SystemExit(main())
