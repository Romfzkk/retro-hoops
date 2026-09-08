# Architecture

Scenes are mostly script-driven. `core/` owns settings and save data, `data/`
owns rosters and seasons, `match/` owns play, `gfx/` owns 3D presentation,
`ui/` owns native menus and HUD, and `net/` owns session setup and replication.
The imported character and textures live in `game/art/`; fonts and menu art
live in `game/assets/`.

`HumanController`, `TeamAI` and network input fill `PlayerIntent`. `PlayerPawn`
reads that intent during physics ticks. Match rules enable movement and actions
only in the appropriate phase, with a separate permission for the free-throw
shooter. CPU shot input stays held through the gather between AI decisions.

`Ball.holder` is the authority for possession. A catch revokes the previous
pawn's ownership. Passes have a target and a lifetime; an uncaught pass becomes
loose. The match resolves scoring before rebound catches, and records an
attempt once. A shot released before the period horn can finish in flight.
A shot stuck above the rim stops being a scoring attempt after eight seconds,
so it cannot suspend the final horn indefinitely. Shooting fouls retain their
own free-throw sequence through the restart.
`_finish()` clears queued actions and timers, parks the ball, and emits once.
The result carries team data so Quick Play does not depend on a career save.

`ShotSolver` combines range-specific ratings, release quality, contest,
movement and fatigue into aim error. It then computes a launch velocity.
The ball follows physics after release. Rim crossings use the segment between
physics samples, preventing a fast ball from skipping the scoring plane.
Rebounds become available after contact or descent below the rim.

| Collision layer | Contents | Collision mask |
|---|---|---|
| World | Court, rim, board, supports | None |
| Ball | Basketball | World |
| Player | Pawn capsules | World |

Player separation and ball interactions are implemented in gameplay code.
The ball does not collide with player capsules. This avoids an outgoing shot
hitting the shooter's own capsule. Damping is replaced explicitly, and the
launch solver compensates for half a gravity step at the configured physics
rate. These constraints belong in code comments because changing them affects
trajectories.

`ModelRig` loads and normalizes the character. `ModelRetarget` builds an
arms-down neutral pose in hierarchy order, then converts animator rotations
into the imported parent's space. `PlayerRig` keeps gameplay measurements
independent of the model and provides hand and sole anchors. The ball anchor
is updated after the current pose; release is dispatched after that update.
Headless match samples retain the imported skeleton and remove its meshes, so
release geometry matches rendered play. See [the import path](character-import.md).

`MenuScreen` builds real buttons and scrolling rows. Its detail area supports
roster and box-score tables. `MatchHud` reads the match phase, clocks, owner,
free throws and active player. It exposes pause and final-result buttons and
reports timing separately from contest pressure. A good timing label does not
guarantee a basket.

The online host runs the simulation and sends snapshots at 24 Hz. The client
sends intent, interpolates positions, and drives approximate animation from
state flags. The host also sends the controlled player slot so the client
marker follows the player actually receiving input. Setup includes the host's actual rosters. Final results are sent
reliably as plain data, then reconstructed into a local `BoxScore`. Ordinary
snapshots cannot overwrite an accepted final result. Input RPCs check the
sender and clamp movement. Button edges use reliable delivery and accumulate
until the next physics tick; movement snapshots cannot clear them. This still
needs a two-machine test with latency and packet loss.

Run the full gate with `python tools/dev/check.py`. The optional grammar check
uses `gdtoolkit==4.5.0`:

```bash
python -m pip install gdtoolkit==4.5.0
python tools/dev/check_syntax.py
```

That parser checks syntax and scene paths only. It cannot check Godot's types,
physics, import behavior or rendering.

For paired samples after the engine gate passes:

```bash
python tools/dev/sample_matches.py --seeds 4 --seconds 120 --output build/samples-after.jsonl
```

The default collects 24 complete games: three matchups, four seeds, and both
home/away orders. Each has one 120-second regulation period and normal overtime.
It uses `--fixed-fps 60`, not a time-scale multiplier. Each JSON line includes
stats, score, elapsed physics time and rule events. A timeout or script error
fails the run. It refuses to overwrite existing results. Keep before and after
files, compare pooled shooting and turnover rates, and inspect outlier games.
No such before/after comparison has been run for this branch.

A single diagnostic match can be invoked directly:

```bash
godot --headless --fixed-fps 60 --path game res://scenes/match.tscn -- --sim 1800 --quarters 1 --quarter-seconds 120 --seed 7 --home 0 --away 16
```

Capture actual rendered screens with a graphics-capable Godot build:

```bash
godot --path game --resolution 1920x1080 res://scenes/main_menu.tscn -- --shot ../build/menu-desktop.png --after 3
godot --path game --resolution 960x540 res://scenes/exhibition_setup.tscn -- --shot ../build/setup-mobile-size.png --after 3
```

Create `build/` first. A small desktop window is a layout check, not Android
hardware validation. Frame capture waits for rendering and cannot run with
`--headless`. The engine-dependent examples above remain unverified here.
