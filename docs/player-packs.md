# Roster packs

The game ships with 30 invented franchises and no real names. A roster pack is
a JSON file you write yourself that renames teams, restyles them and replaces
their players.

Packs live in `user://packs/`, which is:

| Platform | Path |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\Retro Hoops\packs\` |
| Linux | `~/.local/share/godot/app_userdata/Retro Hoops/packs/` |
| Android | `Android/data/com.retrohoops.game/files/packs/` |

Open **Roster Packs** from the main menu to see what has been found, turn packs
on and off, write an example file to start from, or open the folder.

Packs are applied when a season is started. Turning one on mid-season does not
rewrite a league already in progress.

## Format

```json
{
  "format": 1,
  "name": "My pack",
  "author": "you",
  "teams": [
    {
      "abbr_match": "BAY",
      "city": "Your City",
      "name": "Your Team",
      "abbr": "YRC",
      "primary": "#204080",
      "secondary": "#f0f0f0",
      "accent": "#101828",
      "replace_roster": false,
      "players": [
        {
          "fn": "First",
          "ln": "Last",
          "num": 7,
          "pos": "PG",
          "h": 190,
          "skin": 3,
          "hair": 1,
          "ratings": { "base": 78, "thr": 88, "pas": 90, "spd": 86 }
        }
      ]
    }
  ]
}
```

### Team fields

| Field | Required | Meaning |
|---|---|---|
| `abbr_match` | yes | Which existing team to replace, by its current abbreviation |
| `city`, `name`, `abbr` | no | New identity. Anything omitted keeps the original |
| `primary`, `secondary`, `accent` | no | Kit and court colours as hex |
| `replace_roster` | no | `true` (default) swaps the roster out, `false` appends |
| `players` | no | The players themselves |

A replaced roster shorter than 12 players is topped up with generated
players, so a two-man pack still leaves a team that can take the floor.

`primary` is the jersey, `secondary` is the trim, numbers and shoes, and
`accent` tints the shorts and the court apron.

### Player fields

| Field | Default | Range |
|---|---|---|
| `fn`, `ln` | required | first and last name |
| `num` | index | 0-99 |
| `pos` | `SF` | `PG` `SG` `SF` `PF` `C` |
| `h` | 198 | height in cm, 150-240 |
| `skin` | 2 | 0-5, lightest to darkest |
| `hair` | 0 | 0 crop, 1 fade, 2 afro, 3 headband, 4 flat top |
| `ratings` | see below | 25-99 each |

### Ratings

`base` sets every rating at once; name individual ones to override it.

| Key | Drives |
|---|---|
| `spd` `acc` | top speed and acceleration, in metres per second |
| `str` | holding position, and how thickly the player is built |
| `vrt` | vertical leap in metres — this is what decides who can dunk |
| `thr` `mid` `cls` | shooting from three, mid-range and close |
| `dnk` `lay` | finishing at the rim |
| `pas` `hnd` | passing and ball security |
| `stl` `blk` `reb` `def` | defence |
| `sta` | stamina drain and recovery |

Ratings are real quantities, not opinions. A player with `vrt` of 40 cannot get
a hand over the rim regardless of everything else, and a 7-footer with a low
`spd` will be beaten down the floor.

## Validation

A pack is checked before anything is applied, and rejected as a whole if
anything is wrong — a bad file can never half-apply and leave your league in a
strange state. Rejections are written to the Godot log with the reason.

Checked: the format version, that `teams` is a non-empty array, that every team
names a target, that colours parse as colours, that positions are known and
that each player has both names. Ratings, heights and numbers are clamped into
range rather than rejected.

## A note on what you put in them

Packs are yours and stay on your machine. Nothing is uploaded and no pack is
distributed with the project. What you choose to type into one is your call.
