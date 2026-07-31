#!/usr/bin/env python3
"""
Find and optionally rename files with non-ASCII characters in their names.

Accepts either one or more files, or a single directory (not both).
Directories are scanned recursively. If no paths are given, the current
directory is used.

By default this runs in dry-run mode and only prints what would change.
Use --apply to perform renames.
"""

from __future__ import annotations

import argparse
import os
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path


def log_print(text: str) -> None:
    print(text, file=sys.stderr)

# Common problematic Unicode characters with reasonable ASCII replacements.
CHAR_REPLACEMENTS: dict[str, str] = {
    "\u00A0": " ",   # no-break space
    "\u2007": " ",   # figure space
    "\u2009": " ",   # thin space
    "\u200A": " ",   # hair space
    "\u200B": "",    # zero width space
    "\u200C": "",    # zero width non-joiner
    "\u200D": "",    # zero width joiner
    "\u202F": " ",   # narrow no-break space
    "\u2060": "",    # word joiner
    "\uFEFF": "",    # zero width no-break space (BOM)
    "\u2018": "'",   # left single quote
    "\u2019": "'",   # right single quote
    "\u201C": '"',   # left double quote
    "\u201D": '"',   # right double quote
    "\u2013": "-",   # en dash
    "\u2014": "-",   # em dash
    "\u2212": "-",   # minus sign
    "\u2026": "...", # ellipsis
}


@dataclass(frozen=True)
class RenamePlan:
    old_path: Path
    new_path: Path
    bad_chars: tuple[str, ...]


def is_ascii(text: str) -> bool:
    return all(ord(ch) < 128 and ch != "_" for ch in text)


def to_ascii_filename(name: str) -> str:
    out: list[str] = []
    for ch in name:
        if ch == ":":
            out.append("_")
            continue

        if ord(ch) < 128:
            out.append(ch)
            continue

        replacement = CHAR_REPLACEMENTS.get(ch)
        if replacement is not None:
            out.append(replacement)
            continue

        # Try transliteration via decomposition first (e.g. "é" -> "e").
        decomposed = (
            unicodedata.normalize("NFKD", ch).encode("ascii", "ignore").decode("ascii")
        )
        if decomposed:
            out.append(decomposed)
            continue

        # Fall back to underscore when no reasonable ASCII form exists.
        out.append("_")

    renamed = "".join(out)
    # Keep output tidy and filesystem-friendly.
    renamed = " ".join(renamed.split())
    return renamed.strip()


def bad_chars_in(text: str) -> tuple[str, ...]:
    return tuple(dict.fromkeys(ch for ch in text if ord(ch) >= 128))


def describe_char(ch: str) -> str:
    code = f"U+{ord(ch):04X}"
    name = unicodedata.name(ch, "UNKNOWN")
    display = repr(ch)[1:-1]
    return f"{display} ({code}, {name})"


def plan_for_file(path: Path) -> RenamePlan | None:
    original_name = path.name
    if is_ascii(original_name):
        return None

    new_name = to_ascii_filename(original_name)
    if not new_name:
        new_name = "_"

    if new_name == original_name:
        return None

    return RenamePlan(
        old_path=path,
        new_path=path.with_name(new_name),
        bad_chars=bad_chars_in(original_name),
    )


def collect_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    seen: set[Path] = set()

    for path in paths:
        if path.is_file():
            candidates = [path]
        elif path.is_dir():
            candidates = [p for p in path.rglob("*") if p.is_file()]
        else:
            raise FileNotFoundError(f"not a file or directory: {path}")

        for candidate in candidates:
            resolved = candidate.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            files.append(candidate)

    return files


def build_rename_plan(paths: list[Path]) -> list[RenamePlan]:
    plans: list[RenamePlan] = []
    for path in collect_files(paths):
        plan = plan_for_file(path)
        if plan is not None:
            plans.append(plan)
    return plans


def apply_renames(plans: list[RenamePlan]) -> None:
    target_to_source: dict[Path, Path] = {}
    for plan in plans:
        if plan.new_path in target_to_source:
            other_source = target_to_source[plan.new_path]
            raise RuntimeError(
                "Rename collision: both "
                f"'{other_source}' and '{plan.old_path}' map to '{plan.new_path}'."
            )
        target_to_source[plan.new_path] = plan.old_path

    for plan in plans:
        if plan.new_path.exists():
            raise RuntimeError(
                f"Target already exists: '{plan.new_path}' (from '{plan.old_path}')."
            )

    for plan in plans:
        os.rename(plan.old_path, plan.new_path)


def format_targets(paths: list[Path]) -> str:
    if len(paths) == 1:
        return str(paths[0])
    return ", ".join(str(p) for p in paths)


def print_plan(plans: list[RenamePlan], paths: list[Path]) -> None:
    targets = format_targets(paths)
    if not plans:
        log_print(f"No non-ASCII filenames found in: {targets}")
        return

    log_print(f"Found {len(plans)} file(s) with non-ASCII characters in: {targets}\n")
    for plan in plans:
        bad_desc = ", ".join(describe_char(ch) for ch in plan.bad_chars)
        log_print(f"- OLD: {plan.old_path}")
        log_print(f"  BAD: {bad_desc}")
        log_print(f"  NEW: {plan.new_path}\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="List and optionally rename files that contain non-ASCII characters."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        default=["."],
        help="Either one or more files, or a single directory (not both). "
        "Directories are scanned recursively. Default: current directory.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply renames. Without this flag, script runs in dry-run mode.",
    )
    parser.add_argument(
        "--print-new-path",
        action="store_true",
        help="Print the new filepath to stdout when exactly one file is renamed "
        "(for capture/piping). Diagnostics stay on stderr.",
    )
    return parser.parse_args()


def resolve_targets(raw_paths: list[str]) -> list[Path] | int:
    """Resolve and validate paths. Returns targets, or an exit code on error."""
    paths = [Path(p).expanduser().resolve() for p in raw_paths]

    for path in paths:
        if not path.exists():
            log_print(f"Error: path does not exist: {path}")
            return 2
        if not path.is_file() and not path.is_dir():
            log_print(f"Error: not a file or directory: {path}")
            return 2

    files = [p for p in paths if p.is_file()]
    directories = [p for p in paths if p.is_dir()]

    if files and directories:
        log_print(
            "Error: specify either file(s) or a directory, not both. "
            "Only one can be specified."
        )
        return 2

    if len(directories) > 1:
        log_print("Error: only one directory can be specified.")
        return 2

    return paths


def main() -> int:
    args = parse_args()
    targets = resolve_targets(args.paths)
    if isinstance(targets, int):
        return targets

    try:
        plans = build_rename_plan(targets)
    except FileNotFoundError as exc:
        log_print(f"Error: {exc}")
        return 2

    print_plan(plans, targets)

    if args.print_new_path and len(plans) != 1:
        log_print(
            f"Error: --print-new-path requires exactly one rename "
            f"(found {len(plans)})."
        )
        return 2

    if not plans:
        return 0

    if not args.apply:
        log_print("Dry-run only. Re-run with --apply to rename files.")
        if args.print_new_path:
            print(plans[0].new_path)
        return 0

    apply_renames(plans)
    log_print("Renames complete.")
    if args.print_new_path:
        print(plans[0].new_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
