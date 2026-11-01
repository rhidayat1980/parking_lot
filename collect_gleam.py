#!/usr/bin/env python3

from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent
OUTPUT_FILE = PROJECT_DIR / "parking_lot_source.txt"

EXCLUDED_DIRS = {"build"}


def collect_gleam_files() -> None:
    gleam_files = sorted(
        path
        for path in PROJECT_DIR.rglob("*.gleam")
        if not any(part in EXCLUDED_DIRS for part in path.relative_to(PROJECT_DIR).parts)
    )

    if not gleam_files:
        raise SystemExit("No .gleam files found.")

    with OUTPUT_FILE.open("w", encoding="utf-8") as output:
        output.write("PARKING LOT — GLEAM SOURCE CODE\n")
        output.write("=" * 80 + "\n")
        output.write(f"Total files: {len(gleam_files)}\n\n")

        for file_path in gleam_files:
            relative_path = file_path.relative_to(PROJECT_DIR)

            output.write("=" * 80 + "\n")
            output.write(f"FILE: {relative_path}\n")
            output.write("=" * 80 + "\n\n")
            output.write(file_path.read_text(encoding="utf-8"))
            output.write("\n\n")

    print(f"Collected {len(gleam_files)} Gleam files.")
    print(f"Output: {OUTPUT_FILE}")


if __name__ == "__main__":
    collect_gleam_files()