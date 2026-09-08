#!/usr/bin/env python3
"""Collect paired AI matches with fixed seeds and unchanged physics timing."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PAIRINGS = [(0, 16), (7, 23), (11, 29)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, default=4, help="Seeds per matchup, with both home/away orders")
    parser.add_argument("--seconds", type=int, default=120, help="Seconds in the sampled regulation period")
    parser.add_argument("--output", type=Path, default=ROOT / "build/balance.jsonl")
    args = parser.parse_args()
    if args.seeds < 2 or args.seconds < 60:
        parser.error("Use at least two seeds and 60 seconds per period")
    godot = os.environ.get("GODOT_BIN", "godot")
    if not shutil.which(godot):
        sys.exit("Godot is missing. Set GODOT_BIN to Godot 4.7.2 standard after importing the project.")
    samples = []
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Refuse to overwrite a previous comparison run.
    with args.output.open("x") as output:
        for home, away in PAIRINGS:
            for seed in range(1, args.seeds + 1):
                for left, right in [(home, away), (away, home)]:
                    command = [godot, "--headless", "--fixed-fps", "60", "--path", str(ROOT / "game"),
                               "res://scenes/match.tscn", "--", "--sim", "1800", "--quarters", "1",
                               "--quarter-seconds", str(args.seconds), "--seed", str(seed),
                               "--home", str(left), "--away", str(right)]
                    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
                    log = result.stdout + result.stderr
                    rows = [line.removeprefix("MATCH_SAMPLE ") for line in log.splitlines()
                            if line.startswith("MATCH_SAMPLE ")]
                    if result.returncode or len(rows) != 1 or re.search(r"SCRIPT ERROR:|Parse Error:|^ERROR:", log, re.M):
                        raise RuntimeError(f"Sample failed for seed {seed}, {left} vs {right}:\n{log}")
                    sample = json.loads(rows[0])
                    if not sample["complete"]:
                        raise RuntimeError("Match timed out before completion")
                    samples.append(sample)
                    output.write(json.dumps(sample) + "\n")
                    output.flush()
                    print(f"{len(samples)}: seed {seed}, {left} vs {right}, score {sample['score']}")
    fga = sum(team["fga"] for sample in samples for team in sample["totals"])
    fgm = sum(team["fgm"] for sample in samples for team in sample["totals"])
    summary = {"games": len(samples), "mean_total_points": statistics.mean(sum(s["score"]) for s in samples),
               "pooled_fg_fraction": fgm / fga if fga else None,
               "mean_shot_clock_violations": statistics.mean(s["events"]["shot_clock"] for s in samples)}
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
