# Character integration

The repository already contains `game/art/player.fbx`, `player_0.png` and an
asset-specific masked texture, `player_kit.png`. No GLB was found. The FBX
source contains one mesh, one material, 25 skeleton nodes and 22 weighted
clusters. Source inspection found 28,508 control vertices, 50,000 faces, no
unweighted vertices and weight sums within about 0.00000015 of 1. Some vertices
have five influences. This does not prove that the imported deformation looks good.

Clothing, skin and hair share a texture. The existing kit shader classifies
texels in the bundled mask. It is not a modular clothing system. The skeleton
has wrists but no finger joints. Animation data exists in the FBX, but its
import configuration disables animation import; no usable authored basketball
clips have been verified.

The adapter preserves imported node transforms, calculates mesh bounds through
nested transforms, normalizes height on a wrapper and turns the bundled +Z
forward model toward gameplay's -Z. It validates required bones, limb chains
and skinned surfaces, and rejects rotation spaces with nonuniform scale or
reflections. The rig regression also checks imported weight sums and skin
binding indices. The adapter keeps imported skin bindings intact.

Retargeting uses the current corrected parent while deriving each limb's
neutral pose. Applying a correction against the original T-pose independently
at every joint rotates the forearm twice. Animator deltas are converted into
the neutral parent's rotation space. Hand anchors refer to the actual wrist
bone and are sampled directly from the skeleton's current global pose.

Gameplay height, shoulder height, reach, capsule dimensions and jump ratings
remain independent of the visual mesh. Simulation-only runs retain the same
skeleton and anchors. Foot correction aligns the lowest sole vertically with
the pawn's floor. It does not lock a stance foot horizontally or solve knees
with IK. Residual sliding, hand intersection and shoulder deformation require
rendered inspection.

Evaluate one player before changing the roster-wide asset:

1. Put an FBX or GLB under `game/devmodels/`. That folder is ignored so exports
   under evaluation are preserved locally without being added accidentally.
   Import it in Godot. Keep its textures next to it.
2. Inspect the skeleton, weights and rest pose in the editor. The current
   adapter expects the Mixamo names listed in `ModelRig.BONE_NAMES`, a single
   skeleton, and the bundled model's forward convention. Other conventions
   need an explicit adapter change, not only renamed bones.
3. Run the bundled one-player regression and preview commands below. Test idle,
   run, dribble, shoot, dunk and defend. The preview uses the same roster player
   for every pose and rejects an unusable imported rig with an error.
4. Check feet on the floor, shoulders through overhead rotation, wrists at the
   ball, release location and landing. Then test the pawn in a real possession.
   A successful import alone is not approval to replace all players.
5. Once the single player is approved, add the asset and its attribution to a
   tracked art folder and update the adapter deliberately. External preview
   assets retain their original materials; the bundled texture mask is not applied.

```bash
godot --headless --path game --import
godot --headless --path game res://scenes/rig_regressions.tscn
godot --path game res://scenes/dev_rig.tscn -- --pose idle --closeup
godot --path game res://scenes/dev_rig.tscn -- --pose shoot --player-model res://devmodels/candidate.glb
```

The imported asset itself has been preserved. This branch changes its adapter
and animation code, but the single-player runtime and visual gates have not
run in this environment. The draft must retain that limitation.

For better hands and motion, the remaining external work is a character with
finger joints and checked shoulder/hip weights, plus usable basketball clips
for locomotion, gather, release, catch, takeoff and landing. Separate materials
or masks are needed before promising independent clothing, hair or skin edits.
