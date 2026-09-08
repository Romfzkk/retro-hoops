# Retro Hoops

A Godot basketball prototype with full-court 5-on-5 and 3-on-3, Quick Play,
a generated 30-team season, and two-player local or direct-connect games.
GDScript builds the court and most scene contents. The player is an imported
FBX, with procedural animation. Menus and the HUD use native Godot controls.

The project declares Godot 4.7. CI pins **Godot 4.7.2 standard**. Desktop uses
Forward+; Android uses the Mobile renderer. Python 3.10+ is needed for the
check and match-sampling scripts. Exporting requires matching Godot templates.

From the repository root, with `godot` on PATH:

```bash
godot --headless --path game --import
godot --path game
python tools/dev/check.py
```

`GODOT_BIN` can select another executable for the Python and shell helpers.
For example, in PowerShell:

```powershell
$env:GODOT_BIN = 'C:\Tools\Godot_v4.7.2-stable_win64_console.exe'
& $env:GODOT_BIN --path game
python tools/dev/check.py
```

`check.py` imports the project, runs the existing self tests and the match,
rig and UI regressions, and treats script errors as failures. Engine checks
and exports have not passed for this branch yet. See
[validation notes](docs/validation.md) for the commands actually run and blockers.

To export after installing the templates:

```bash
mkdir -p build/windows build/android
godot --headless --path game --export-release "Windows Desktop" ../build/windows/RetroHoops.exe
godot --headless --path game --export-debug "Android" ../build/android/RetroHoops.apk
```

Android also needs JDK 17, the Android SDK and a configured debug keystore.
Follow [Godot's Android setup](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)
for the SDK packages and editor paths. These export recipes are not a claim
that this branch has produced a working build.

| Action | Keyboard | Primary gamepad |
|---|---|---|
| Move | WASD or arrows | Left stick |
| Sprint | Shift | Right trigger |
| Shoot or jump to contest | Space | A |
| Pass or attempt a steal | E | X |
| Dunk modifier while driving and shooting | Q | B |
| Switch defender | F | Y |
| Pause or back | Esc | Start |

Hold and release Shoot for a jumper. Timing, ratings, movement, fatigue and
contests influence the launch. Close attempts become layups, or dunks when
the approach and reach permit. Assisted shooting ignores release timing.
Player one uses the keyboard or first connected pad. Player two uses the
second connected pad. Phones show a touch stick and action buttons.

Menus support mouse, keyboard and controller focus. Long lists scroll;
Details opens the side content at narrow sizes. Online play continues while
the match menu is open. A lost connection stops the match and offers an exit.
Online games require the same game version on both machines. LAN discovery
and direct IP use UDP ports 27016 and 27015 respectively.

Career data stays in `user://career.json`. Saves are written to a temporary
file before replacement, with the previous file retained as `career.json.bak`.
[Roster packs](docs/player-packs.md) are local JSON files in `user://packs/`.

Known limits:

- Character animation still needs visual approval. Sole alignment is vertical
  only, with no planted-foot IK. The FBX has no finger joints, and its single
  texture combines clothing, hair and skin. There is no interchangeable hair
  or general clothing customization. See [character integration](docs/character-import.md).
- Inbounds are automatic restarts. There are no substitutions, foul-outs,
  charges, traveling, backcourt or three-second violations. 3-on-3 uses the
  same full-court rules. The AI has spacing and cuts, but no playbook.
- Online play has one human per team, approximate remote animation and no lag
  compensation. Network delivery and disconnect changes need a two-machine test.
- Android rendering, touch layouts and performance need device testing.
  Current screenshots in `docs/screenshots/` are historical, not verification
  of this branch. No representative balance comparison has run for these changes.

[Architecture and development tools](docs/architecture.md) describe the match
lifecycle, seeded sampling and screenshot commands.

Code is MIT, see [LICENSE](LICENSE). Barlow and Bebas Neue use the SIL Open Font
License, preserved in `game/assets/fonts/`. The imported player and poster have
no separate attribution files in this checkout; their source still needs documenting.
