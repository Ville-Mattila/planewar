# sim/relay - MODULE.md

Contract for `godot/src/sim/relay/**`: the Relay Station capture and hold of 02 s5.3 (GD-23; R0 C2-20) and the Solar Plateau
centres the power model reads (02 s8.4). R0 B.9 A-21 split: `SimWorld` and every type other lanes may name stay in
`sim/MODULE.md`. A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Who holds each neutral Relay Station: a Hauler DOCKED on its pad for `capture_s` with no enemy ship or ground unit within `contest_radius_m` hands the structure its own `team` and `owner`; contested progress pauses, the Hauler leaving resets it, recapture is the same rule; the capture score (`ScoreKeeper.relay_captured`), the hold score (`relay_held`) and the `RELAY_CAPTURED` / `RELAY_CONTESTED` alerts. Loads the Solar Plateau centres of a map into `Economy.set_plateaus`. Not here: the pad service (`sim/docking/` reads the structure's team, harvest I8), sensors and visibility (`sim/vision/` reads `team` and the def's `sensor_radius`), placing the Relay Station from a map (`neutral_structures`, a maps / loader follow-up), any `SimView` read of the progress. |
| Lane owner tier | Sonnet against this file; Opus reviews |
| May depend on | `core`, `content`, `sim` (inside the sim module) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (GD-23); `EconomyHub.relay.step` runs in step 10 right after `Docking`; no new saved section (`SimSerialize.FORMAT` unchanged: progress is the structure's `timer_a`) |

## Public API

```gdscript
class_name RelayCapture extends RefCounted                                   # GD-23; EconomyHub.relay, step 10 after Docking
var capture_s: float;  var contest_radius_m: float                           # scoring.json `relay.capture_s` / `relay.contest_radius_m`
func _init(store: EntityStore, defs: WorldDefs, score: ScoreKeeper, events: SimEvents)   # score may be null (no result counters)
func step(dt: float) -> void                                                 # every Relay Station in ascending slot order
func progress_s(relay: int) -> float                                         # slot: seconds of capture progress, 0 for none
func contested(relay: int) -> bool                                           # slot: the capture is paused by an enemy this tick
# SunPath.load_plateaus(map_dir) -> PackedVector3Array (documented in sim/economy/MODULE.md): the Plateau centres of a map, R9
```

Numbers: `scoring.json` `relay` (`capture_s` 20, `contest_radius_m` 300, plus the existing `capture` 300 and `hold_per_min` 10;
schema `scoring.schema.json`). A Relay Station is any structure of def `relay_station`; a Hauler is a ship whose resolved def has `cargo_ice` > 0.

## Invariants

- R1 Capture (02 s5.3). A relay with a live Hauler DOCKED on it (`F_DOCKED`, `link` = the relay's id) whose team is not the relay's
  accumulates `dt` per tick in its own `timer_a`; at `capture_s` its `team` and `owner` become the Hauler's, `timer_a` returns to 0
  and the progress starts again for the next rule. The holder (a neutral relay has team 255) keeps the pad until then.
- R2 Contest. While any live ship or ground unit of a team other than the Hauler's (neutral excluded) is within `contest_radius_m`
  (centre distance) the progress does not move; it keeps its value (`contested` true).
- R3 Reset. The progress is 0 on any tick with no capturing Hauler on the pad: it left or died, it is not a Hauler, it is of the
  holder's team, or its team changed. A fresh arrival starts from 0.
- R4 Recapture. A relay held by team A is captured by team B by R1-R3 unchanged; there is no extra delay, no shield, no cap.
- R5 Events. Completing a capture emits one `ALERT` `RELAY_CAPTURED` (a = kind, b = the relay id, team = new holder, reason byte = the
  new owner) and, when a team lost it, one `RELAY_CONTESTED` to that team. The first contested tick of a stretch emits one
  `RELAY_CONTESTED` to the capturing team. No other event.
- R6 Score. A capture calls `ScoreKeeper.relay_captured(owner, possessed)` once (Pilot side when the Hauler is possessed); every tick a
  held relay (owner a player slot) calls `relay_held(owner, dt / 60)` (Commander side).
- R7 Readers. The change is the structure's `team` / `owner` bytes: `SimView.team` / `owner`, `Vision` (next pass: the holder's
  `sensor_radius` and `deck_reveal_radius` cover, the loser's go), `PadService` (serves the holder only) and AI-22 `Perception`
  (re-reads `team` every refresh, 05 C18) follow with no further code.
- R8 State (S4). The progress is `timer_a`, the contested flag `timer_b` and the candidate team `link` (team + 1, 0 none) of the relay
  structure, all in `EntityStore`; a restored world continues byte for byte. No new saved section.
- R9 Plateau. `SimWorld.load_map` of a map id feeds `load_plateaus` to `Economy.set_plateaus`; the radius is `economy.json`
  `solar_plateau_radius_m` and the multiplier `solar_plateau_mult` (02 s8.4). The flat datum has none.
- R10 Open pad. A structure that is `invulnerable`, has `pads` > 0 and is not `buildable` (the Relay Station) takes ships of every team
  as a landing / DOCKED pad (`WorldDefs.open_pad_by_def`, `Collision.open_pad`: no RAM, a C_PAD contact), because a capturer must dock on a
  pad it does not hold. `Docking` serves a docked ship only when the pad's team equals the ship's (harvest I8: the holder only); an enemy
  or neutral pad launches and queues nothing special. Tests: `test_relay_effects.gd`.
- R11 Cost. `step` returns at once when the store holds no Relay Station def instance; otherwise it scans the (<= 480) structures for the
  def, then per relay one pass over the ships for a docked Hauler and, only with one on the pad, the ships and ground units for a contest.
  No Dictionary, no per-entity allocation.

## Data owned

Nothing outside `EntityStore` (R8).

## Events emitted / consumed

Emits `ALERT` `RELAY_CAPTURED` and `RELAY_CONTESTED` (R5). Consumes nothing.

## Performance budget

Not a hot path: one structures scan per tick (<= 480 def-id compares) and, per relay, one pass over <= 200 ships; the unit scan
only while a Hauler sits on a pad. Bound in `test_relay_perf.gd` (PerfGate).

## Test entry points

`godot/test/unit/sim/relay/test_relay_capture.gd` (R1-R6), `test_relay_effects.gd` (R7-R10), `test_relay_perf.gd` (R11); fixtures `relay_test_kit.gd`.

## How to add X

- **A second neutral objective with its own rule:** a new def, a branch in `RelayCapture._is_target`, its numbers in `scoring.json` `relay` (schema first) and a test here.
- **Reading the progress in the HUD:** needs a `SimView` method; that is a contract change for the Architect (`needs sim/ui`).
