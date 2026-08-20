#!/usr/bin/env python3
"""Run one build command with bounded process-group memory use."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time


RESOURCE_LIMIT_EXIT = 86


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-process-mib", type=int, default=12_288)
    parser.add_argument("--max-group-mib", type=int, default=32_768)
    parser.add_argument("--poll-seconds", type=float, default=2.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    if args.max_process_mib < 1 or args.max_group_mib < args.max_process_mib:
        parser.error("memory limits must be positive and group must be at least process")
    if args.poll_seconds < 0.25:
        parser.error("poll interval must be at least 0.25 seconds")
    return args


def process_group_rss_kib(process_group: int) -> tuple[int, int, int]:
    result = subprocess.run(
        ["/bin/ps", "-axo", "pid=,pgid=,rss="],
        check=True,
        capture_output=True,
        text=True,
    )
    total = 0
    largest = 0
    largest_pid = 0
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) != 3:
            continue
        pid, pgid, rss = (int(field) for field in fields)
        if pgid == process_group:
            total += rss
            if rss > largest:
                largest = rss
                largest_pid = pid
    return total, largest, largest_pid


def stop_group(child: subprocess.Popen[bytes]) -> None:
    process_group = child.pid
    try:
        os.killpg(process_group, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        child.wait(timeout=10.0)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process_group, signal.SIGKILL)
    except ProcessLookupError:
        pass
    child.wait()


def main() -> int:
    args = parse_args()
    child = subprocess.Popen(args.command, start_new_session=True)
    process_group = child.pid
    max_process_kib = args.max_process_mib * 1024
    max_group_kib = args.max_group_mib * 1024

    def forward(signum: int, _frame: object) -> None:
        try:
            os.killpg(process_group, signum)
        except ProcessLookupError:
            pass

    signal.signal(signal.SIGINT, forward)
    signal.signal(signal.SIGTERM, forward)

    while child.poll() is None:
        try:
            total_kib, largest_kib, largest_pid = process_group_rss_kib(process_group)
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            print(f"warning: memory guard could not sample process RSS: {error}", file=sys.stderr)
            time.sleep(args.poll_seconds)
            continue
        if largest_kib > max_process_kib or total_kib > max_group_kib:
            print(
                "error: memory guard stopped the build: "
                f"largest PID {largest_pid} used {largest_kib // 1024} MiB; "
                f"process group used {total_kib // 1024} MiB; "
                f"limits are {args.max_process_mib} MiB and {args.max_group_mib} MiB",
                file=sys.stderr,
            )
            stop_group(child)
            return RESOURCE_LIMIT_EXIT
        time.sleep(args.poll_seconds)
    return child.returncode


if __name__ == "__main__":
    raise SystemExit(main())
