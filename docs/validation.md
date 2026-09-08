# Validation record

Baseline: `8088e3ea15c676ac1ce42ed6bd3434a0ec28f006` on `main`, with a clean
working tree. No `AGENTS.md` or additional project instructions were found.
Work is on `codex/gameplay-rig-ui` in [draft PR 1](https://github.com/Romfzkk/retro-hoops/pull/1).
This record covers checks attempted on September 7 and 8, 2026.

| Check | Result | What it establishes |
|---|---|---|
| Baseline GDScript grammar | 59 scripts parsed | Syntax only |
| Current grammar and scene references | 63 scripts, 17 scenes, zero failures | Grammar and referenced scene files exist |
| Python compilation | `python -m compileall -q tools/dev` passed | Helper scripts compile |
| Shell syntax | `bash -n tools/dev/run.sh` passed | Helper shell syntax is valid |
| Patch whitespace | `git diff --check` passed | No whitespace errors in the patch |
| Engine gate | `python tools/dev/check.py` exited 1 because Godot is missing | No runtime tests ran |
| Paired match samples | Runner exited 1 because Godot is missing | No match outcomes collected |
| Windows and Android exports | Not run | Engine and export dependencies unavailable |
| Rendered desktop/mobile inspection | Not run | No new screenshots or visual approval |

The optional syntax command was executed with gdtoolkit 4.5.0 available on
Python's module path. It is not the Godot parser or type checker.

Godot was not installed in the execution environment. Earlier engine downloads
failed with proxy connection timeouts. The September 8 attempt ended with
`network approval was cancelled before a decision was returned`. No download
or installation was reported as successful.

The [baseline CI run](https://github.com/Romfzkk/retro-hoops/actions/runs/34149958505)
failed in Self tests without reporting any steps; Windows build was skipped.
The [gameplay/HUD CI run at 35fcd223](https://github.com/Romfzkk/retro-hoops/actions/runs/34253653075)
reported the same failure shape. Available job metadata did not expose the
underlying cause. The baseline job-log request returned 404 BlobNotFound.
These failures do not establish whether any of the engine regressions pass.

New regression cases cover exclusive possession, pass expiry, free-throw
accounting and sequencing, foul/rebound ordering, buzzer shots, duplicate
completion, a ball stuck above the rim, interception credit, rim-plane
crossings, shot-clock suspension, CPU gather timing, pose-before-release
ordering, Quick Play results and client final-result delivery. Rig checks use
one imported player to inspect neutral limb directions, anchors, measurements,
normalized skin weights and transformed bounds. UI checks cover input edges,
touch holds, save validation and menu bounds at four viewport sizes. All of
these engine-dependent cases still need execution.

The FBX, both character textures and the MIT license are byte-identical to the
baseline. The poster was moved into `game/assets/art/` without changing its
bytes. A limited scan of 177 tracked files found no private-key headers,
GitHub token patterns or AWS access-key IDs. No identical art or font files
were found. A tracked Python bytecode cache was removed, and local caches,
exports and credential files are ignored. No Git history was rewritten.

Base accuracy weights and aim-error distribution were kept. Fixes to launch origins, CPU gathers,
contests, fouls and clocks can change results. The paired sampling runner now
uses the same skeleton as rendered play and records seeds, both home/away
orders, complete results and rule events. Balance effects remain unmeasured.

Before approving the draft, run the engine gate, inspect a single player in
all preview poses and a real possession, compare paired match samples, and
capture actual desktop and Android-sized screens. Test two connected machines
for roster identity, switching, reliable button edges, disconnects and final
results. Android also needs a hardware run. Passing a grammar check does not
establish visual quality or gameplay quality.
