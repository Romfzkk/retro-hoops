#!/usr/bin/env python3
"""Run Godot import and regression scenes, including script errors in the exit status."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT_BIN", "godot")


def run(args):
    result = subprocess.run([GODOT, "--headless", "--path", str(ROOT / "game"), *args],
                            capture_output=True, text=True, timeout=120)
    output = result.stdout + result.stderr
    print(output, end="")
    if result.returncode or re.search(r"SCRIPT ERROR:|Parse Error:|^ERROR:", output, re.M):
        raise RuntimeError("Godot check failed: " + " ".join(args))


def main():
    if not shutil.which(GODOT):
        sys.exit("Godot is missing. Install 4.7.2 standard and set GODOT_BIN to its executable.")
    for args in [["--import"], ["res://scenes/self_test.tscn"],
                 ["res://scenes/match_regressions.tscn"], ["res://scenes/rig_regressions.tscn"],
                 ["res://scenes/ui_regressions.tscn"]]:
        run(args)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
