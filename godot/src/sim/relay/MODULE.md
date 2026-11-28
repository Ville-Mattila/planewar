# sim/relay - MODULE.md

Contract for `godot/src/sim/relay/**`: the Relay Station capture and hold of 02 s5.3 (GD-23; R0 C2-20) and the Solar Plateau
centres the power model reads (02 s8.4). R0 B.9 A-21 split: `SimWorld` and every type other lanes may name stay in
`sim/MODULE.md`. A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Who holds each open pad (a def with `capture_s`, today the neutral Relay Station): a capturer (`captures`, the Hauler) DOCKED on its pad for the def's `capture_s` with no enemy ship or ground unit within its `contest_radius_m` hands the structure its own `team` and `owner`; contested progress pauses, the Hauler leaving resets it, recapture is the same rule; the capture score (`ScoreKeeper.relay_captured`), the hold score (`relay_held`) and the `RELAY_CAPTURED` / `RELAY_CONTESTED` alerts. Loads the Solar Plateau centres of a map into `Economy.set_plateaus`. `MapRelays` (GD-51, R0 B.30 A-150) spawns the map's Relay Stations in `SimWorld.load_map`. Not here: the pad service (`sim/docking/` reads the structure's team, harvest I8), sensors and visibility (`sim/vision/` reads `team` and the def's `sensor_radius`), where a map puts the Relay Station (the maps lane bakes it), any `SimView` read of the progress. |
| Lane owner tier | Sonnet against this file; Opus reviews |
| May depend on | `core`, `content`, `sim` (inside the sim module) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (GD-23); `EconomyHub.relay.step` runs in step 10 right after `Docking`; no new saved section (`SimSerialize.FORMAT` unchanged: progress is the structure's `timer_b`, R8). R0 B.30 A-146..A-149 applied (round 2) |

## Public API

```gdscript
class_name RelayCapture extends RefCounted                                   # GD-23; EconomyHub.relay, step 10 after Docking
func _init(store: EntityStore, defs: WorldDefs, score: ScoreKeeper, events: SimEvents)   # score may be null (no result counters)
func step(dt: float) -> void                                                 # every open pad in ascending slot order
class_name MapRelays extends RefCounted                                      # GD-51; called by SimWorld.load_map
static func spawn(map_dir: String, defs: WorldDefs, terrain: Terrain, store: EntityStore, applier: CommandApplier, tick: int) -> int   # count spawned
# SunPath.load_plateaus(map_dir) -> PackedVector3Array (documented in sim/economy/MODULE.md): the Plateau centres of a map, R9
```

Numbers (R0 B.30 A-148): `structures.json` per def, required as a pair: `capture_s` (relay_station 20) and `contest_radius_m` (300); the def
needs `pads` >= 1 and `pad_radius_m` > 0 (`validate_content`). A target is any structure whose def has `capture_s` > 0 (`WorldDefs.capture_s_by_def`,
`contest_radius_by_def`; `open_pad_by_def`); a capturer is a ship whose def has `captures: true` in `ships.json` (`capturer_by_def`, the Hauler only).
`scoring.json` `relay` keeps the score numbers `capture` 300 and `hold_per_min` 10. There is no public accessor of the progress for other lanes (A-150).

## Invariants

- R1 Capture (02 s5.3). An open pad with a live capturer DOCKED on it (`F_DOCKED`, its `link` = the pad's id) whose team is not the pad's
  accumulates `dt` per tick in its own `timer_b`; at the def's `capture_s` its `team` and `owner` become the capturer's and all three
  fields return to 0. The holder (a neutral pad has team 255) keeps the pad until then.
- R2 Contest. While any live ship or ground unit of a team other than the Hauler's (neutral excluded) is within `contest_radius_m`
  (centre distance) the progress does not move; it keeps its value and `timer_a` is 1.0.
- R3 Reset. `timer_b`, `link` and `timer_a` are 0 on any tick with no capturer of a non-holder team DOCKED on the pad (it left or died, it
  is not a capturer, its team is now the holder's). A docked capturer whose id differs from `link` zeroes the progress and takes `link`.
- R4 Recapture. A relay held by team A is captured by team B by R1-R3 unchanged; there is no extra delay, no shield, no cap.
- R5 Events. Completing a capture emits one `ALERT` `RELAY_CAPTURED` (a = kind, b = the relay id, team = new holder, reason byte = the
  new owner) and, when a team lost it, one `RELAY_CONTESTED` to that team. The first contested tick of a stretch emits one
  `RELAY_CONTESTED` to the capturing team. No other event.
- R6 Score. A capture calls `ScoreKeeper.relay_captured(owner, possessed)` once (Pilot side when the Hauler is possessed); every tick a
  held relay (owner a player slot) calls `relay_held(owner, dt / 60)` (Commander side).
- R7 Readers. The change is the structure's `team` / `owner` bytes: `SimView.team` / `owner`, `Vision` (next pass: the holder's
  `sensor_radius` and `deck_reveal_radius` cover, the loser's go), `PadService` (serves the holder only) and AI-22 `Perception`
  (re-reads `team` every refresh, 05 C18) follow with no further code.
- R8 State (S4; A-149, 03 s3.2 rows 31-33). On the pad structure: `timer_b` = capture progress in seconds, `link` = EntityId of the capturer whose
  capture runs (0 none; `SimView.link(pad)` hands it out, the candidate team is `team[slot(link)]`), `timer_a` = 1.0 while the capture is
  paused by a contest, else 0.0. All in `EntityStore`; a restored world continues byte for byte. No new saved section.
- R9 Plateau. `SimWorld.load_map` of a map id feeds `load_plateaus` to `Economy.set_plateaus`; the radius is `economy.json`
  `solar_plateau_radius_m` and the multiplier `solar_plateau_mult` (02 s8.4). The flat datum has none.
- R10 Open pad (R0 B.30 A-146, A-147). A capturer, and nobody else, gets the A-109 shape on an open pad it does not hold: no RAM above the
  deck at any offset, a C_PAD contact inside the pad volume (`Collision.open_pad`, `Collision.capturer`, set from `WorldDefs`); any other ship
  rams it at every altitude, and a capturer is rammed below the deck plane and by any other enemy pad. `Docking` serves a docked ship only while
  the pad's team equals its team (docking D14; the holder and its teammates only) and never gates the launch. Tests: `test_collision.gd`,
  docking `test_service.gd` / `test_launch.gd` / `test_touchdown.gd`, `test_relay_effects.gd`.
- R11 Cost. `step` returns at once when no def carries `capture_s`; otherwise it scans the (<= 480) structures for the
  def, then per open pad one pass over the ships for a docked capturer and, only with one on the pad, the ships and ground units for a contest.
  No Dictionary, no per-entity allocation.

`MapRelays.spawn` reads `<map_dir>/features.json`: first `nodes[]` entries with `kind` "relay_station" (the 02 s9.1 `ring_features`;
field `dir`), then `neutral_structures[]` entries with `def` "relay_station" (`dir`, optional `facing_dir`), each block in file order. One
finished structure each (owner and team 255, F_BUILDING clear, on `Terrain.surface_point`, `up` = the entry's `dir`, radial (R0 B.33 A-157, GD-52: as every built structure, so Collision's pad plane and `Economy.solar_factor` see a level deck), `fwd` = the facing projected on the tangent plane there or the
tangent frame). Missing file, no entry or an unknown def spawns none. Skipped on a deserialize (the store comes from the bytes). The two blocks never overlap by
design (03:992: `neutral_structures[]` holds the non-template structures, the template Relay Stations come from `ring_features`), so there is no
de-duplication here. needs maps: a bake-side check that no `neutral_structures` entry restates a ring relay (`moonbake validate`). Each spawn
leaves a SPAWN event in the queue; a caller that scans events for its own spawn drains first. Today no shipped bake carries an entry (the
maps lane's follow-up); the loader is covered by fixtures in `test/unit/sim/relay/fixtures/`.

## Data owned

Nothing outside `EntityStore` (R8).

## Events emitted / consumed

Emits `ALERT` `RELAY_CAPTURED` and `RELAY_CONTESTED` (R5). Consumes nothing.

## Performance budget

Not a hot path: one structures scan per tick (<= 480 def-id compares) and, per relay, one pass over <= 200 ships; the unit scan
only while a capturer sits on a pad. Bound in `test_relay_perf.gd` (PerfGate).

## Test entry points

`godot/test/unit/sim/relay/test_relay_capture.gd` (R1-R6), `test_relay_effects.gd` (R7-R10), `test_relay_perf.gd` (R11), `test_map_relays.gd` (GD-51), `test_relay_radial_up.gd` (GD-52, A-157); fixtures `relay_test_kit.gd`.

## How to add X

- **A second capturable pad:** give its def `capture_s`, `contest_radius_m`, `pads` and `pad_radius_m` in `structures.json`; nothing else (A-148). Test here.
- **Reading the progress in the HUD:** `SimView.link` / `team` and the two ALERTs exist; a progress bar needs a new `SimView` method; that is a contract change for the Architect (`needs sim/ui`).
