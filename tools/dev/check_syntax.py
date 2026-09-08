#!/usr/bin/env python3
"""Check GDScript grammar and scene references without claiming engine validation."""
from pathlib import Path
import re
import sys

try:
    from gdtoolkit.parser import parser
except ImportError:
    sys.exit("Install the optional parser with: python -m pip install gdtoolkit==4.5.0")

ROOT = Path(__file__).resolve().parents[2]
failures = []
scripts = sorted((ROOT / "game").rglob("*.gd"))
for path in scripts:
    try:
        parser.parse(path.read_text(encoding="utf-8"), gather_metadata=True)
    except Exception as error:
        failures.append(f"{path.relative_to(ROOT)}: {error}")

scenes = sorted((ROOT / "game/scenes").glob("*.tscn"))
for scene in scenes:
    for resource in re.findall(r'path="res://([^"]+)"', scene.read_text(encoding="utf-8")):
        if not (ROOT / "game" / resource).is_file():
            failures.append(f"{scene.relative_to(ROOT)}: missing {resource}")

print(f"Syntax: {len(scripts)} scripts, {len(scenes)} scenes, {len(failures)} failures")
for failure in failures:
    print(failure)
sys.exit(bool(failures))
