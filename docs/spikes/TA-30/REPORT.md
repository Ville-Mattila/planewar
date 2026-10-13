# TA-30 REPORT: S-FLIGHT-1 flight spike

| | |
|---|---|
| **Task** | TA-30 |
| **Spike** | S-FLIGHT-1 (01 Appendix A; 03 s14.6) |
| **Branch** | `spike/TA-30-flight` (PR #37) |
| **Author / tier** | sim-engineer / Opus |
| **Date** | 2026-10-13 |
| **Owner gate decision** | PENDING HUMAN: tester sessions per TESTER_PROTOCOL.md |

## 1. Scope
- R = `Sphere.PLANET_RADIUS` flat-shaded icosphere: level 6, 81,920 faces, colour jitter, decorative boulders. No LOD, no economy, flat `Terrain`.
- `step_ship` unchanged, with the lift A/B switch on F2 or in the panel.
- 30 Hz tick, 60 fps render interpolation using `Engine.get_physics_interpolation_fraction()`.
- 06 s5.2 chase camera stub plus a hover view.
- Straight gun (slugs carry the shooter's velocity) and lead pips. 10 air targets and 5 ground targets.
- 2 bombs with the 6 s / 15 Hz impact ring.
- Stub pad (`pad_radius_m` 10) with the tail-down rule of 03 s6.4 / R0 B.5: damage band, crash, LandingGrade q and grade, DOCKED service timers, thrust to launch. No level-landing variant.
- Auto-dock assist (05 L4-L6 gains), forced ceiling release, overspeed damage.
- KBM (MOUSE_AIM/DIRECT, power/lever), gamepad DIRECT, touch ARCADE per 06. FULL/RAW tiers.
- Tuning panel with anchor bands and patch export.
- CSV telemetry in `user://s_flight_1/`, with a download button on web. 03 says `flight_log.jsonl`; the brief asked for CSV.

Defs: `rules.json` and `structures.json` come from `content/defs`. `ships`, `projectiles` and `weapons` are copies of the canonical fixture until GD-02 lands them; the loader then picks up `content/defs` automatically.

## 2. Harness
- Measurements: `timeout 600 godot --headless --path <repo>/godot res://spikes/s_flight_1/harness/sf_harness.tscn -- --csv-dir=<dir>`
- Frame stats: `--autofly --frames=N` (windowed)
- Device smoke: `--smoke=kbm|pad|touch`

Dev box: Windows 11, RTX 5070 Laptop, Godot 4.7.2 Compatibility, 1280x720.

## 3. Measurements
See the table above and `harness_output.txt`. Additional results:
- **Flip** at cruise: speed after the flip is 105.9 m/s, then 94.4 after 1 s and 72.7 after 3 s at thrust 0.5. The nose reverses but the velocity keeps the old heading (dot 1.00 / 0.99 / 0.94).
- **Hover throttle:** Dart 0.25, Bomber 0.43. Tilt authority at 1 g vertical: Dart 75.5 deg, Bomber 64.6 deg.
- **Build and tick cost:** scene build 188 ms; spike world tick 66-137 us. Neither is on the sim path.

## 4. Pass / fail
- **PASS:** co-altitude hits, AoA <= 6 deg (`speed_scaled`), anchors, tail-down only, interpolation, input classes built.
- **PENDING HUMAN:**
  - three novices within 10 min;
  - < 20 % crashes in minutes 5-10;
  - Raw mouse tester within 15 attempts;
  - median "feels like a plane" >= 4/5;
  - phone frame time.

## 5. Fallback taken (data)
03 s14.6's fail path "widen the auto-dock assist" applied:
- **Problem:** with 05's values, DOCK pressed at flight speed overshot the 150 m radius and the assist let go (45/200 runs lost).
- **Change:** `latch_release_mult` 5 (once engaged, the assist holds while DOCK is held, out to 750 m) and `transition_max_tilt_deg` 75 for L4 only.
- **Result:** 200/200.

## 6. Plan changes requested
**Anchor patch to 02:** none. Proposed `flight_common` fields:
- `landing_damage_tilt_deg` 45: the 25-45 deg band has no field today;
- `auto_dock_latch_mult` 5;
- `auto_dock_transition_tilt_deg` 75;
- `brake_fade_mps` 10: TA-12's `_BRAKE_FADE_MPS`.

**Kinematics / sim requests (Architect):**
1. **Flip:** behaviour does not match 03 s5.3's "reverses heading, ~25 % loss". Either change the doc or rotate the velocity during the flip.
2. **Scrape damage per contact:** the ground push-out makes a sliding ship bounce, so scrape damage repeats: 100 HP in 0.7 s in one harness run. End a contact episode only after the ship has cleared the ground.
3. **Pad entry while in contact:** a ship sliding onto the pad while already in ground contact is never evaluated for landing. Evaluate on entering the pad volume too.
4. **Fuel burn:** 02 s2.3 boost, brake and idle burn is missing from `step_ship`.
5. **Auto-dock radius:** say whether it is 3D or horizontal (the spike reads 3D).

**06 requests (Sonnet):**
- **Hover camera:** the chase camera sits under a tail-down ship. The spike blends to a belly-side, 20-deg-down view between 30 and 60 deg of nose pitch; adopt it.
- **Auto-level:** it fights the tail-down hover. The spike disables it above 45 deg pitch.
- **MOUSE_AIM clamp:** the 85 deg clamp leaves 0.5 m/s^2 of hover drift.

Suggested follow-up: S-FLIGHT-1 human sessions + Android APK frame time (owner + Sonnet).

## 7. Notes
- Web `user://` is IndexedDB, so testers must press "Save telemetry CSV".
- Nothing to file upstream.


