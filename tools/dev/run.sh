#!/usr/bin/env bash
# Import fresh class names, then run a scene and optionally capture a frame.
# usage: run.sh <scene> [png-path] [extra args...]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="$ROOT/tools/Godot_v4.7.2-stable_win64_console.exe"
SCENE="${1:?scene required}"
SHOT="${2:-}"
shift 2 2>/dev/null || shift $#

"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1

ARGS=(--path "$ROOT/game" --resolution 1600x900 "$SCENE" --)
[ -n "$SHOT" ] && ARGS+=(--shot "$SHOT")
ARGS+=("$@")

timeout 90 "$GODOT" "${ARGS[@]}" 2>&1 \
  | grep -viE "^$|vulkan api|godot engine v|https://godotengine|NVIDIA|Unreferenced static string"
