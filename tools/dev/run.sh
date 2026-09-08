#!/usr/bin/env bash
# Usage: run.sh <scene> [capture.png] [scene flags...]
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
scene="${1:?scene required}"
shift
capture=""
if (( $# > 0 )) && [[ "$1" != --* ]]; then
    capture="$1"
    shift
fi
if ! command -v "$godot_bin" >/dev/null; then
    echo "Godot is missing. Set GODOT_BIN to the Godot 4.7.2 executable." >&2
    exit 1
fi
"$godot_bin" --headless --path "$project_root/game" --import
args=(--path "$project_root/game" --resolution 1600x900 "$scene" --)
if [[ -n "$capture" ]]; then
    args+=(--shot "$capture")
fi
exec "$godot_bin" "${args[@]}" "$@"
