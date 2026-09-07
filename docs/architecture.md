# Architecture

## Layout

```
game/
  project.godot
  scenes/            thin scene files; the scripts build their own contents
  assets/fonts/      two OFL fonts, the only binary assets in the project
  scripts/
    core/            settings, save data, court dimensions, collision layers
    data/            league generation, teams, roster packs, season simulation
    match/           pawns, ball, rules, clock, AI, camera, box score
    gfx/             court surface, arena, crowd, player rig, jumbotron
    ui/              theme, menus, HUD, touch controls
    net/             session, LAN discovery, state replication
    tools/           dev only: frame capture, headless sim, shot lab
```

Scenes are deliberately almost empty. Each one is a root node with a script
that builds its contents in code. Nothing is laid out in the editor, so a
change is a diff you can read rather than a binary scene file.

## One intent, three sources

`PlayerIntent` is a struct of what a player is trying to do this frame:
a movement vector, an aim vector and the button edges. It is filled in by:

- `HumanController` from the keyboard, a specific pad, or the touch overlay
- `TeamAI` from its decision model
- `MatchSync` from a remote player's uploaded input

`PlayerPawn` reads only the intent. It has no idea which of the three wrote it,
so movement, shooting, passing and dunking exist once instead of three times,
and the AI is exercised by exactly the code a human drives.

## Shooting

`ShotSolver` is pure static maths and is unit-testable on its own.

1. `accuracy()` folds the shooter's rating for that range, the release quality,
   how contested they are, how fast they are moving and fatigue into one number
   between 0 and 1.
2. `aim_point()` turns that number into an offset from the middle of the rim.
   The error is biased toward short and long rather than left and right,
   because that is how real misses distribute.
3. `flight_time()` and `launch_velocity()` solve for the velocity that reaches
   that point, on an arc that puts a jumper near a 45 degree entry angle.
4. The ball is launched and then left completely alone.

Nothing steers the ball in flight and there is no "did it go in" roll. A miss
is a real trajectory, which is why it can rim out, bank in off the glass, or
rattle and drop.

Two engine details are compensated for explicitly, both of which broke shooting
badly before they were found:

- The ball uses `DAMP_MODE_REPLACE`. Under the default `COMBINE`, the world's
  area damping is added to the body's own, and even 0.1 bleeds enough speed
  over a 1.3 second flight to land every shot a metre short.
- The launch adds half a physics step of gravity. Godot integrates with
  semi-implicit Euler, which lands a projectile `0.5 * g * dt * t` below the
  analytic parabola — about 10cm over a long shot, enough to clip the front of
  the rim on a shot aimed dead centre.

## Collision layers

Three layers, in `core/collision_layers.gd`:

| Layer | Contents | Collides with |
|---|---|---|
| World | floor, rim, backboard, stanchion | — |
| Ball | the ball | World |
| Player | pawn capsules | World |

The ball deliberately does not collide with players. It is released from above
the shoulder, which is inside the shooter's own capsule, so physical contact
there deflects every shot. Blocks, steals and interceptions are decided by the
rules instead, where they can be weighted by ratings.

## Rendering

Everything in 3D is generated:

- **Court** — drawn once into an offscreen viewport with Godot's 2D API, then
  used as the floor texture. Baking it beats laying decal geometry over the
  floor: no z-fighting, and the lines stay sharp at any camera height.
- **Players** — a hierarchy of joints with primitives hung off them. Each
  segment is capped with a sphere matching its end radius, which is what stops
  limbs reading as disconnected tubes. Posed by writing rotations, blended
  toward each frame. No skinning, no imported model.
- **Crowd** — one MultiMesh with a body and head welded into a single mesh, so
  the whole bowl is one draw call. Sway and cheer happen in the vertex shader.
- **Numbers** — one 10x10 atlas rendered once, indexed by UV offset, wrapped
  onto the torso as a curved patch so it sits on the shirt.

Balance runs skip geometry entirely: `PlayerRig` builds the joint hierarchy and
the body measurements but no meshes, and the arena is floor collision only.

## Networking

Host authoritative. The host runs physics, the AI for every player nobody is
driving, and all rule decisions. At 24Hz it sends:

- per pawn: position, yaw, speed, packed state flags, stamina
- the ball: position, velocity, state
- the scoreboard: score, period, clocks, phase, possession

Clients simulate nothing. Pawns and the ball are flagged `network_remote` and
interpolate toward the last snapshot; the client's AI and rules are skipped
entirely. The visitor uploads its intent every frame and the host applies it
through the same `HumanController` path a local player uses.

Hosts announce themselves once a second over UDP broadcast, so a game on the
same network appears in a list without anyone typing an address.

## Tools

`tools/` is dev-only but ships in the build, because it is inert without its
flags and gives a release build a real diagnostic.

- `frame_capture.gd` — `--shot out.png [--after 6]` saves a frame and quits.
- `sim_probe.gd` — `--sim 330` plays a headless game and prints a box score.
  It deliberately does not offer a speed multiplier: `Engine.time_scale` scales
  the physics delta, which changes the trajectories being measured.
- `shot_lab.gd` — fires known shots through the physics engine to check the
  solver, and separately integrates thousands analytically to map accuracy onto
  make percentage. The shooting balance is tuned against its output.
