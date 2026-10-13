# C2 - Cross-doc consistency and completeness review

| | |
|---|---|
| **Project** | PLANEWAR (codename) |
| **Document** | Review C2: cross-document consistency and completeness of the stage-2 drafts |
| **Status** | Review v1.0 (stage 3, critic) |
| **Date** | 2026-10-09 |
| **Reviewed** | 01 (spine, v1.0), 02, 03, 04, 05, 06, 07, 08 (all Draft v0.1 stage 2), research R1-R3 for fact checks |
| **Lens** | Every number, name, signature, enum, JSON field, file path and module boundary across 01-08; completeness against the four launch modes; work-breakdown coverage, duplicate IDs and dangling dependencies |
| **Tie-breaker** | 01. Where 01 is silent, the doc that 01 s12 makes the owner of the topic wins (02 numbers and content, 03 sim/engine/baker, 04 wire/backend, 05 control/AI, 06 input/UI, 07 art/audio/map look, 08 nothing binding until adopted). |

## How to use this review

Issues are numbered C2-01 ... C2-40, most severe first. Each names the affected docs and a required fix that a reviser can apply without re-deriving the reasoning. Where several docs disagree, the fix states the canonical value and which sections change. Issues against 01 are escalations to the owner (they are marked "01" and are genuine ambiguities or errors, not preferences).

Severity: **blocker** = two or more lanes would build incompatible artefacts on the same files from day one; **major** = contradiction, missing piece or wrong number that causes rework; **minor** = clarity, polish or a local mismatch with an obvious fix.

Summary counts: 2 blockers, 23 major, 15 minor (C2-22 is minor and listed in Part B).

---

## Part A. Cross-reference findings

### C2-01 (blocker) Def schemas: 02 and 03 specify different field names and different def files for the same JSON

**Problem.** Both docs claim the JSON field names of `ships.json` and siblings, and they disagree on almost every flight field:

| Meaning | 02 s2.2 / s2.3 (column header) | 03 s5.1 / s9.2 |
|---|---|---|
| cruise | `v_cruise` | `cruise` |
| boost speed / duration / cooldown | `v_boost`, `boost_duration_s`, `boost_cooldown_s` | `boost_speed`, `boost_s`, `boost_cd_s` |
| dive cap | `v_dive_max` | `dive_max` |
| turn rates | `pitch_rate_dps`, `yaw_rate_dps`, `roll_rate_dps` | `rate_pitch`, `rate_yaw`, `rate_roll` |
| flip | `flip_duration_s`, `flip_cooldown_s` | `flip_s`, `flip_cd_s` |
| radius / sensor | `bounding_radius`, `sensor_radius` | `radius`, `sensor_m` |
| cost / build | `cost_ore`, `cost_ice`, `build_time_s` | `cost {ore, ice}`, `build_s` |
| damping | per ship `k_side`, `k_up` (0.5-0.8 / 0.10-0.20) | global `rules.k_side`, `rules.k_up` |
| thrust knee / retro | `flight_common.eff_fade_start`, `flight_common.brake_factor` | `rules.thrust_knee`, `rules.retro_factor` |
| over-dive damage | `flight_common.overspeed_dps` = 10 HP/s flat | `ship.overdive_dps` = 10 HP/s per 10 m/s over |
| Dart `a_thrust` | 24 m/s^2 | 45 m/s^2 ("derived") |
| angular acceleration | absent | `rate_accel` 720 deg/s^2 |

The def file sets also differ: 02 s1.1 has `economy.json`, `match_rules.json`, `modes.json`, `bot_promises.json`, `projectiles.json`, `towers.json`, `scoring.json`/`medals.json`/`progression.json`; 03 s9.2 has `rules.json` (with `match {core_exposure_s, hard_end_s}`, `salvage_fraction`, `wreck_ttl_s`), `resources.json` (02 puts resources in map recipes), `bots.json`, no `ProjectileDef` at all (03 `ContentDB` has no `projectile()` accessor although 02 s1.2 and the `ProjectileStore` need one). Doctrines: 02 s7 uses a generic selector/modifier schema resolved by `ContentDB.resolve_for_doctrine()`; 03 s9.2 uses a fixed `multipliers {ship_speed, ...}` object applied by `Economy.apply_doctrine(team)`, and 03 s15.3 says content "does not apply doctrines". The first tasks of the content lane (GD-01..GD-07 versus TA-07, TA-09, TA-10) author the same files twice with incompatible schemas, and `Kinematics.step_ship` (TA-12) cannot be written against both.

**Required fix.**
1. 02 owns gameplay def field names and the gameplay def file list (02 s1.1). 03 s5.1 table and 03 s9.2 table are rewritten to 02's names exactly as in the left column above. Add `rate_accel_dps2` (starting value 720) as a new column in 02 s2.2 for all ships.
2. Keep one `rules.json` (03) for world constants only: `gravity` 6.0, `ceiling_soft` 1500, `ceiling_hard` 2000, `tick_hz` 30, `caps {standard, reduced}`, `sim_budget_profile[]`, `debug_commands`, `profile_enabled`. Remove from 03's `rules.json`: `k_side`, `k_up`, `thrust_knee`, `retro_factor` (now per-ship or `ships.json.flight_common`), `match {...}` (now 02 `match_rules.json`), `salvage_fraction`, `wreck_ttl_s` (now 02 `economy.json` `wreck_fraction`, `wreck_lifetime_s`). Add a "World constants" row to 02 s1.1 pointing at `rules.json`.
3. 03 s5.3 pseudocode reads `def.k_side`, `def.k_up` (per ship), `flight_common.eff_fade_start`, `flight_common.brake_factor`; over-dive damage = `flight_common.overspeed_dps` (flat, 02). Delete 03's Dart `a_thrust` 45 and its "derived" note; cite 02 (24) as the S-FLIGHT-1 starting value.
4. 03 adds `ProjectileDef` (fields of 02 s4.2), `ContentDB.projectile(id)`, and stores a projectile def index (not a weapon index) in `ProjectileStore`.
5. Doctrines: adopt 02 s7 selector schema. `ContentDB.resolve_for_doctrine(doctrine_id) -> ResolvedDefs` is a pure function returning an immutable resolved table built once at `SimWorld.load_map` (outside the content hash). 03 s9.2 doctrine row and the `Economy.apply_doctrine` sentence are replaced by this; 03 s15.3 responsibility line becomes "applies doctrine modifiers as a pure function producing resolved views; never mutates base defs".
6. Delete 03 `resources.json` row; resource node values live in the map recipe `resources` block (02 s9.1, see C2-02).
7. Work seeds: TA-07 shrinks to `rules.schema.json` + `map_recipe.schema.json`; TA-10 shrinks to `rules.json`; GD-01..GD-05 own all other gameplay schemas and files; GD-06 is merged into TA-09 (one ContentDB task, depends on GD-01..05); GD-07 stays (doctrine resolver, depends on TA-09).

### C2-02 (blocker) Maps: three different map sets, recipe schemas, file names and biome ids

**Problem.**
- Map ids: 02 s9.2 `halcyon_mare`, `shatter_belt`, `rimewater` (all 8-slot, resources and campaign use defined); 07 s9.4 `cradle`, `anvil`, `glassfield`; 03 TA-16 `equinox_8` plus "a 4-slot and a 2-slot map" (which also contradicts 01 s5.6/s5.7: every map has 8 equatorial slots and unused slots keep 50 % yield).
- Characters: 02 Rimewater is "highlands everywhere, ice-rich"; 07 Glassfield is "huge flat maria, few features". Campaign use differs (02: Halcyon M1-M3, Shatter M4/M6, Rimewater M5/M7/M8; 07: Cradle 1-3, Anvil 4-6, Glassfield 7-8).
- Recipe schema: 03 s8.1 (`features[]` stamps, `resource_nodes[]`, `start_slots[]`, `biomes{}`), 07 s9.1 (`symmetry` wedge, `regions`, `craters.explicit/scatter`, `slots`, `resources.use_template`, `poles`, `boulder_fields`) and 02 s9.1 (`resources` block with `slot_features`, `ring_features`, `pole_features`, `unused_slot_yield`) are three incompatible shapes for the same `recipe.json`. 08 adds `meteor_sets`.
- Output files: 03 s8.3 `face{0..5}.height.u16`, `face{f}.biome.u8`; 07 s9 `heights_f0..5.u16`, `biome_f0..5.u8`. Baker CLI: 03 `python -I -m moonbake bake|validate`; 07 `python tools/moonbake/bake.py --validate --preview`.
- Biome ids: 03 s8.1 `default 0, mare 1, highland 2, crater_floor 3, rim 4, rille 5, cold_trap 6, solar_plateau 7, ore_field 8, ejecta 9`; 07 s2.1 `mare 0, highland 1, crater_floor 2, rim_ejecta 3, cold_trap 4, ore_field 5, solar_plateau 6, rille_floor 7`. Ramp texture: 03 s7.8 256 x 8 indexed by height; 07 s3.1 16 x 64 `moon_ramp.png` indexed by a ramp value.
- Tasks: GD-22, TA-15/TA-16, ART-28..ART-31 and FEAT-25 all write map recipes or validators.

**Required fix.**
1. Canonical v1 map ids are 02's: `halcyon_mare`, `shatter_belt`, `rimewater`, with 02 s9.2 characters and campaign use. 07 s9.4 is rewritten: Cradle -> `halcyon_mare` (characters agree), Anvil -> `shatter_belt` (characters agree), third column replaced by `rimewater` with 02's character (highlands everywhere except a narrow equatorial mare strip; Ore leaner, Ice richer; mid traps at lat -35; Midnight nodes 6,000/0.9). `glassfield` moves to 07 Open questions as a v1.x candidate. 07's campaign-use row is replaced by 02's.
2. 03 TA-16 becomes "test maps only: `tiny_test` (sim and AI scenarios, 05 s11.2) and the three S-WORLD-1 radius variants"; v1 maps are ART-28 (`halcyon_mare`), ART-29 (`shatter_belt`), ART-30 (`rimewater`) for terrain and GD-22 for the `resources` block.
3. 03 owns `tools/schemas/map_recipe.schema.json`. 03 s8.1 is rewritten to contain: 07 s9.1 authoring blocks (`symmetry`, `base_noise`, `regions`, `craters.explicit`, `craters.scatter`, `rilles`, `slots`, `poles`, `boulder_fields`, `biome_rules`), 02 s9.1 `resources` block verbatim, 08 `meteor_sets`, plus 03's `schema_version`, `seed`, `radius_m`, `face_resolution`, `relief`, `neutral_structures`, `rules_overrides`. 03's flat `features[]`/`resource_nodes[]` become the baker's internal expanded form written to `features.json`, not author input.
4. Output names are 03 s8.3 (`face{f}.height.u16`, `face{f}.biome.u8`, `face{f}.slope.u8`, `face{f}.path.u8`, `features.json`, `meta.json`, `preview.png`); 07 s9 sentence edited to match. CLI is `python -I -m moonbake bake|validate|preview <recipe>`; 07 s9.2 step 8 and s9.5 heading edited; 07's checks M1-M10 become `moonbake validate` checks implemented in TA-15; ART-31 is merged into TA-15 (preview part).
5. Biome ids: 07 s2.1 table is canonical (07 owns the ramp). 03 s8.1 `biomes` object, 03 s8.2 stamp biome assignments and 03 s7.8 ramp sampling are changed to 07's ids, 07's `moon_ramp.png` (16 x 64) and 07 s3.1 ramp-value formula. 03 cross-doc line to 07 ("Biome ids 0-9 and the 256 x 8 colour ramp") is deleted.

### C2-03 (major) Enumerations: SimEvent, Command and alert kinds have no single append-only list

**Problem.** Ordinals matter (03 s15.4 "never reorder: the codec and replays depend on ordinal values"), yet additions are scattered: 01 s9.4 has 18 `SimEvent.Kind`; 03 adds `CAP_REACHED, WRECK_SPAWNED, WRECK_SALVAGED, CEILING_RELEASE, HANDOVER, PLAYER_ELIMINATED`; 02 s21 assumes `LOCK_ACQUIRED, LOCK_BROKEN, CAPTURE_PROGRESS, CAPTURED, SALVAGE_DELIVERED, LANDING, SHIELD_COLLAPSE`; 04 s5.4 uses a `POSSESS_REQUESTED` event; 08 SL-1 instead extends `DOCKED` with grade fields and needs `HIT`/`DEATH` to carry attacker/killer. `Command.Kind`: 03 adds `DEBUG_SPAWN, DEBUG_SET`; 05 AR-1 adds `SET_ADJUTANT` (and 05 s8 still says "assumed TOGGLE_ADJUTANT payload on TOGGLE_AUTO_REPLENISH"). Alert kinds have no owner at all: 05 uses `PENDING_ORDER, POSSESS_REQUEST, LINK_WEAK, ADJUTANT`; 06 s7.4 uses `CORE_UNDER_ATTACK ... HANDOVER_REQUEST ... FACTORY_IDLE`; 02 uses `storage_full`, `tower_offline`, "waiting for Ice"; 08 uses `RELAY_CONTESTED, RELAY_CAPTURED, METEOR_WARN`; 07 s8.1 maps alert sounds to its own names. 04 s3.6 event codec covers only 01's kinds.

**Required fix.** 03 s15.4 gains an "Enumerations (append-only; ordinals frozen)" block, mirrored in `sim/MODULE.md`:
- `SimEvent.Kind`: 0-17 = 01 s9.4 order; 18 CAP_REACHED, 19 WRECK_SPAWNED, 20 WRECK_SALVAGED, 21 CEILING_RELEASE, 22 HANDOVER, 23 PLAYER_ELIMINATED, 24 LOCK_ACQUIRED, 25 LOCK_BROKEN, 26 CAPTURE_PROGRESS, 27 CAPTURED, 28 SALVAGE_DELIVERED, 29 LANDING (payload: grade, q, manual, hot; replaces 08's extra DOCKED fields), 30 SHIELD_COLLAPSE, 31 POSSESS_REQUESTED. `HIT` payload: target, attacker, damage (u16), part; `DEATH`: entity, killer, cause.
- `Command.Kind`: 0-12 = 01; 13 SET_ADJUTANT (05 AR-1), 14 DEBUG_SPAWN, 15 DEBUG_SET. Delete the "TOGGLE_ADJUTANT payload" sentence from 05 s8.
- New `sim/alert_kind.gd` `enum AlertKind` = union of 06 s7.4 kinds + `PENDING_ORDER`, `LINK_WEAK`, `ADJUTANT`, `ORDER_OVERRIDDEN` (05) + `STORAGE_FULL`, `TOWER_OFFLINE`, `WAITING_FOR_ICE`, `ICE_LOW` (02/06) + `RELAY_CONTESTED`, `RELAY_CAPTURED`, `METEOR_WARN`, `DUSK_WARN` (08); 05's `POSSESS_REQUEST` and 06's `HANDOVER_REQUEST` become one name, `HANDOVER_REQUEST`.
- 04 s3.6 event codec table lists a payload layout for every kind above; 06 `alerts.json` maps every `AlertKind`; 07 s8.1 alert sound ids are keyed by `AlertKind` in `alerts.json`, not by event.
- This also answers 03's AR-1 (append-only enum growth is a MODULE.md change); the owner should accept it.

### C2-04 (major) Module layering: auto-dock, AI hook, safety handoff and UI/input type access contradict 01 s9.2 or each other

**Problem.**
- 03 s5.5 puts steering in `sim_ai/steering.gd` (`Steering.input_toward`) and 03 s6.4 says auto-dock "is an input-side assist in `sim_ai/steering.gd` invoked by `Orders`": sim calling sim_ai violates 01 s9.2, and client prediction (net) cannot call sim_ai either. 05 s1.2 solves it by placing pure controllers in `sim/steer/`; 04 s18 assumes `ClientSession` calls `Assist.apply()`.
- AI integration point: 03 s4.1 runs AI think/act as steps 3-4 inside `SimWorld.step()`; 05 s1.3 wants `SimWorld.set_ai_hook(SimAiHook)` inside the step; 04 s7 calls `_bots.tick(_world.view(), _command_sink)` in `ServerSession.tick()` before `_world.step()`. 03's public API has no `set_ai_hook` and no `CommandSinkBase`.
- Safety handoff: 04 s5.4/s18 says "`Autopilot.safety_handoff(entity)` is called by the sim"; that is a sim -> sim_ai call. 05 s2.4 implements it as an overlay set by `ControlMachine` (sim) and executed by `Overlays.run_safety` (sim_ai).
- 06 A1: `input` needs `PilotInput`; `ui` needs `SimView`, `SimEvent`, `Command`. 08 s10 assumes `ui`/`input` get `Terrain.height_at`. 02 s16.3 `MissionRuntime` takes a `CommandSink` (a sim_ai class) although `campaign` may not depend on sim_ai.

**Required fix.**
1. Escalate 06 A1 to the owner as an 01 s9.2 amendment, extended: `input` may reference `PilotInput`; `ui` may reference `SimView`, `SimEvent`, `Command`, `CommandResult`, `PilotInput`, `AlertKind` and read-only `Terrain` (for HUD AGL, Cruise, RouteRecorder); `campaign` may reference `CommandSinkBase`. `tools/deps.json` (TA-02) encodes this.
2. 03 s5.5 rewritten: autopilots produce `PilotInput` through `FlightController.track_velocity()` in `sim/steer/flight_controller.gd` (05 s5.2). 03 s6.4 last sentence rewritten: auto-dock is `Assist.auto_dock()` in `sim/steer/assist.gd`, applied by `SimWorld.step()` in an "assist substitution" sub-step between AI act and kinematics, and by `Prediction` on the client.
3. 03 s15.4 adds `func set_ai_hook(hook: SimAiHook) -> void` and the abstract classes `SimAiHook` and `CommandSinkBase` (05 s1.3) to the sim public API; 03 s4.1 steps 3-4 read "AI hook (sim_ai via SimAiHook)".
4. 04 s7 step 4: replace `_bots.tick(_world.view(), _command_sink)` with a comment that bots run inside `_world.step()` through the AI hook; `ServerSession.add_bot()` forwards to `AiDriver.add_bot()`.
5. 04 s5.4 release diagram and s18 row 05: replace "Autopilot.safety_handoff(entity)" with "ControlMachine sets overlay SAFETY; sim_ai Overlays.run_safety executes it (05 s2.4)".
6. 02 s16.3: `MissionRuntime._init(mission: MissionDef, sink: CommandSinkBase)`.

### C2-05 (major) SimView accessors and their replication: needed by 05, 06, 08, provided by nobody

**Problem.** 03 s15.4 adds only `visible_ids, ships, structures, wrecks, order_kind/target/pos, cargo, cargo_kind, link, flags, radius, def_kind, team_state, player_state, terrain_height, match_phase, match_clock_s`. Missing and requested elsewhere: 05 s14 (`order_head`, `order_issuer`, `service_state`, `pad_queue`, `projectiles_near`, `ai_tag`, `field_remaining`, `path_grid_version`), 06 s16 (`tick`, `boost_state`, `flip_cooldown01`, `dock_state`, `service_progress`, `nearest_friendly_pad`, `pad_occupant`, `pending_order`, `standing_order`, `incoming_rockets`, `stockpile_cap`, `power_balance`, `unit_count`, `supply01`, `production_queue`, `production_progress01`, `tech_available`, `auto_replenish_target`, rockets count), 08 (`player_score`). `NetSimView` must answer the same calls (contract test, 01 s9.4) but 04's pilot block carries only fuel, ammo, bombs, "heat", hull, lock; TEAM_STATE has no score; there is no replication of production queues, pending orders, `ai_tag` or supply pools.

**Required fix.**
1. 03 s15.4 `SimView` adds, with types: `tick() -> int`, `boost_state(id) -> int`, `flip_cooldown01(id) -> float`, `rockets(id) -> int`, `dock_state(id) -> int`, `service_progress(id) -> Vector3` (fuel, ammo, repair 0..1), `service_state(id) -> int`, `pad_queue(pad) -> PackedInt32Array`, `pad_occupant(pad) -> int`, `nearest_friendly_pad(id) -> int`, `order_head(id) -> OrderSpec`, `order_issuer(id) -> int`, `pending_order(id) -> OrderSpec`, `incoming_rockets(id) -> int`, `projectiles_near(p, r, team_mask) -> PackedInt32Array`, `ai_tag(id) -> int`, `field_remaining(node) -> int`, `path_grid_version(face) -> int`, `stockpile_cap(team) -> Vector2i`, `power_balance(team) -> Vector2`, `unit_count(player) -> int`, `supply01(id) -> float`, `production_queue(factory) -> PackedInt32Array`, `production_progress01(factory) -> float`, `tech_available(team, def_id) -> bool`, `auto_replenish_target(player, def_id) -> int`, `player_score(slot) -> Vector2i`. `standing_order` = `order_head`.
2. 04 s3.3/s3.4 adds a replication column for each: own possessed unit in the pilot block (`boost_state`, `flip_cooldown01`, `rockets`, `dock_state`, `service_progress`, `incoming_rockets`; delete the undefined `heat` byte); `ai_tag` u8 in tier A/B flags for own-team entities; own-team factories' queues and progress in a new reliable `TEAM_DETAIL` message at 2 Hz (queues, replenish targets, supply pools, pending/standing order heads of own units); `stockpile_cap`, `power_balance`, `unit_count`, scores in `TEAM_STATE`. Fields not replicated return the def default and set the `unknown` bit (04 s5.6), listed explicitly.
3. Add one 04 work seed: "NET-39 TEAM_DETAIL message and NetSimView accessors for 03 s15.4 additions" (Sonnet, depends NET-17).

### C2-06 (major) Orders: storage, payload and vocabulary differ between 03, 04, 05, 06 and 08

**Problem.** 03 s3.2 stores one order as SoA fields (`order_kind/target/pos`, `saved_order_*`, `pending_order_*`); 05 s2.1/s3.1 uses side-table queues of up to 8 `OrderSpec` with `points` (PATROL 2-8 waypoints), `haul_mode`, `flags` (QUEUE, PREPEND, LOW), `issuer`, `progress`. 04 s2.5 ORDER payload carries only `order_kind`, ids, one `pos` or `target_entity` and `queue_flag`: PATROL waypoints, HAUL mode and FLAG_LOW cannot be sent. 04 V-ORD allows towers only HOLD/GUARD while 05 s3.2 allows ATTACK (manual target) on towers. 06 s7.2 resolves "tap Relay Station with ships" to `ORDER return(pad)` while 05 uses `HAUL` with `haul_mode = CAPTURE`. 08 adds PATROL_ROUTE, ATTACK_VIA, SUPPLY_DROP and an ESCORT payload (leader, slot, focus, mode) that 05's `OrderSpec` lacks. 03 s15.4 says the vocabulary file is `orders.json`; 05 s3.3 uses `order_rules.json`.

**Required fix.**
1. 05 is the owner. 03 s3.2 fields 17-25 are replaced by: `order_kind` (u8, head kind cache for replication and HUD) plus a side table `orders` owned by `sim/orders/order_queue.gd` (05 s1.2) holding the standing queue and the pending queue (max 8 each); `saved_order` is the standing queue while POSSESSED (05 s2.1). Update 03's bytes-per-slot total.
2. 04 s2.5 ORDER payload becomes: `order_kind u8, flags u8 (QUEUE, LOW), haul_mode u8, count u8, ids[count] u32, target u32, point_count u8 (0-16), points[point_count] vec3q` (and route waypoints in 08's 8-byte form for PATROL_ROUTE/ATTACK_VIA); max payload <= 256 B (fits 08's 134 B). V-ORD: towers accept ATTACK, HOLD, GUARD.
3. 06 s7.2: Relay Station target with a Hauler selected -> `ORDER haul(station, CAPTURE)`; with other ships -> `ORDER guard(station)`.
4. File name is `order_rules.json` (03 s15.4 "How to add an order kind" edited).
5. 08's PATROL_ROUTE, ATTACK_VIA and SUPPLY_DROP are appended to `OrderSpec.Kind` only when the owner adopts the shortlist; 05 s3.1 gains `escort_slot`, `focus`, `escort_mode` fields at that time. Until then 05 is unchanged and 08 marks them "pending adoption".

### C2-07 (major) AI state is defined twice (03 EntityStore vs 05 AiState)

**Problem.** 03 s3.2 fields 42-46 (`ai_next_think`, `ai_target`, `ai_goal`, `ai_mode`, `ai_speed`) live in the sim's EntityStore and 03 s19 asks 05 to "use the ai_* SoA fields exactly as named"; 05 s4.3 defines its own `AiState` SoA in sim_ai with `mode`, `target`, `guidance_vel`, `tti`, `timer`, `fire_mask`, `path`, serialized by `AiDriver` into `SimWorld.serialize()`. Two copies of AI state diverge and sim would own data only sim_ai writes. 05 s6.1 also needs a replicated `ai_tag`, which has no sim field.

**Required fix.** Adopt 05: delete 03 s3.2 fields 42-46 (and their 25 B/slot from the total) and add one field `ai_tag` (u8, written via `CommandSinkBase.set_ai_tag(id, tag)`, replicated per C2-05). 03 s19 row 05 is edited accordingly. 03 s15.4 serialization invariant S4 states that `SimWorld.serialize()` appends the AI hook's opaque bytes (05 s1.3).

### C2-08 (major) Possession hand-over and silent-pilot rules contradict between 04 and 05

**Problem.**
| Topic | 04 | 05 |
|---|---|---|
| Hand-over gap | server applies **A's last input held** (s5.4) | `LINK_BRIDGE` overlay; "p's last input is never replayed for q" (s2.5, C10) |
| Silent pilot (link up, no INPUT) | reuse last input 6 ticks, then neutral thrust 0.5; at 60 ticks **release** with `RELEASED(DISCONNECT)` (s5.1, s5.5) | C13: decay stick 50 %/tick from 10 ticks, `LINK_BRIDGE` at 60 ticks, **state stays POSSESSED** until transport drop (SC-25) |
| Request expiry | V-REQ: request < 30 s old | 10 s (s2.1, C10, C17) |
| `RELEASED` reasons | PLAYER, DEATH, CEILING, HANDOVER, DISCONNECT, INVALID, ADMIN | VOLUNTARY, CEILING, DISCONNECT, HANDOVER, DEATH, MATCH |

06 s16 adds a third reading ("neutral input, then safety-handoff release after 05's timeout").

**Required fix.** 05 owns control semantics.
1. Hand-over: 04 s5.4 last paragraph replaced by "Between T and B's first input the server runs `LINK_BRIDGE` (05 C10): pull up if TTI < 2 s, else hold velocity; A's input is not replayed." 04 `handoff_test` acceptance changed to "LINK_BRIDGE <= one RTT; no terrain contact".
2. Silent pilot: 04 s5.1 jitter-buffer bullet: missing input -> reuse previous input for up to 10 ticks with axes decayed 50 % per tick (05 C13), then `LINK_BRIDGE`; the unit stays POSSESSED until the transport times out (60 s web / 15 s native), which triggers C12. Delete 04 s5.5 "treated identically to a disconnect" sentence. 06 s16 row 05 updated to match.
3. Request expiry 10 s everywhere (04 V-REQ, 06 s7.6 toast already 8 s: fine).
4. One `ReleaseReason` enum in `sim/control/control_machine.gd`: `PLAYER, DEATH, CEILING, HANDOVER, DISCONNECT, MATCH, INVALID, ADMIN`; 05 renames VOLUNTARY -> PLAYER; 04 RELEASED reason byte uses it.

### C2-09 (major) PilotInput layout and per-entity meaning differ across 03, 04, 05 and 06

**Problem.** 03 s15.4 assumes 8 bytes = u8 thrust, i8 x3, u8 buttons, **u24 tick**; 04 s2.4 uses bytes 5-6 for `aim_yaw`/`aim_pitch` (tower aim offsets) and one `tick_lo` byte; 05 s1.1 and 06 s3.2 drive towers by `pitch`/`yaw` as **slew rates** (no aim offsets). Ground units: 05 s1.1 BRAKE = stop; 06 s3.2 BRAKE = reverse. Redundancy: 04 INPUT `count` 1-3; 03 s12.3 says slow clients send "15 Hz with 6-tick redundancy".

**Required fix.**
1. Towers use `pitch`/`yaw` as slew rates (05/06). 04 s2.4 bytes 5-6 become `reserved` (must be 0; V-INP checks), as 04 s16 item 2 already offers; delete `aim_*` from V-INP and from 04 s18 row 05. 03 s15.4 `PilotInput.to_bytes` comment changed to "04 s2.4 layout: u8 thrust, i8 pitch/yaw/roll, u8 buttons, 2 reserved, u8 tick_lo".
2. Ground units: BRAKE = stop when moving forward, reverse at <= 3 m/s after 0.5 s held (one rule in 05 s1.1; 06 s3.2 table cites it).
3. 03 s12.3: replace "6-tick redundancy" with "INPUT packets carry `count` up to 3 (04 s2.3); a slow client sends every other tick with count 3". Or raise 04's `count` max to 6 and INPUT max size to 60 B; pick the first (no protocol change).

### C2-10 (major, 01 escalation) Landing attitude: 03 implements a level landing, 05 a tail-down landing

**Problem.** 01 s3.1.4 says "pitch within 25 degrees of the pad normal". 03 s6.4 tests `fwd.dot(up_pad)` "within 25 degrees of perpendicular to the pad normal" (level, aircraft-style). 05 s5.5 and OQ-1 read it as a tail-down powered landing (forward/thrust axis within 25 degrees of the normal) and asks 07 for tail landing legs; 07's recipe cards (s4.5) have no landing gear either way; 06 s6.4 gauge is "pitch from pad normal". Physics favours 05: thrust acts only along body forward (01 s3.1.1) and there is no lift, so a level hull at <= 15 m/s cannot hold sink; with `a_thrust` 13 (02 Bomber) a 25 degree nose-up attitude yields 13 x sin 25 = 5.5 m/s^2 < g = 6. The landing is "the signature moment" (01 P2); two lanes would build opposite rules.

**Required fix.** Escalate to the owner as a clarification of 01 s3.1.4 with the default "tail-down powered landing: the body forward (thrust) axis within 25 degrees of the pad normal at touchdown". Until answered: 03 s6.4 condition becomes `fwd.dot(up_pad) >= cos(25 deg)`; 02 s17.1 grade column "degrees" is defined as the angle between body forward and pad normal; 06 s6.4 gauge label "tilt from pad normal"; 07 s4.5 recipe cards add `HP_Gear_*` tail pads and landing struts on all five ships and the Dart style frame (ART-06) shows the landing pose; S-FLIGHT-1 (03 s14.6) records both feel and success rate and may overturn it.

### C2-11 (major) Projectile and motion constants in 03 contradict 02's defs

**Problem.** 03 s5.3, s5.4 and s6.1 hard-code behaviour that 02 s4.1-4.2 defines differently: slug gravity (03 none, 02 `gravity: true`), slug radius (0.3 vs 0.5/0.6), bomb arm time (0.3 s vs `arm_s` 0.5), bomb structure blast radius (15 m vs 20 m; ships 15 m), rocket turn rate and lock cone (120 deg/s and 30 deg half-angle vs 90/75 deg/s and 20/360 deg per weapon), rail slug (4,000 m/s hitscan vs 1,500 m/s with 1.7 s flight that 02 s4.4 uses as the counter), no `siege_shell` kind in `ProjectileStore`, landing damage (03 `x 0.5`, 02 full ratio), ground slope speed (03 `clamp(1 - slope/30, 0.3, 1)`, 02 `1 - 0.6 * slope/max_slope_deg`). Hard-coding them also breaks ADR-09 ("every numeric anchor ends up in a def file").

**Required fix.**
1. 03 s5.4, s6.1, s6.4 and s5.3 ground paragraph read every one of these from `ProjectileDef`/`WeaponDef`/`GroundUnitDef`/`flight_common` (02 names) and quote 02's values as examples only.
2. Slug gravity: keep 03's AR-4 to the owner ("slugs ignore gravity"); default until answered = no gravity; 02 s4.2 sets `gravity: false` for `slug_light`, `slug_heavy` and `rail_slug`; 06 s6.3 lead formula drops the `0.5 g t^2` term for slugs.
3. Rail: 1,500 m/s per 02 (not hitscan); 03 `ProjectileStore.kind` adds `SIEGE_SHELL` and stores `ProjectileDef` index (C2-01).

### C2-12 (major) Signature and class-name collisions across docs

**Problem.**
- `Kinematics.step_ship`: 01 s9.4 `(p, v, b, input, def, dt) -> ShipState`; 03 s5.2 `(s: ShipState, input, def, rules, terrain, dt)`; 04 s5.3 reconcile calls the 01 form.
- `Build.can_place`: 02 s6.2 `(player, def_id: StringName, center_dir, yaw_steps) -> Reject` with 13 reasons; 03 s15.4 `(def_id: int, cell, rotation, team) -> CommandResult` (no Outpost reasons); 06 s7.3 `(def, cell, rotation, view, terrain) -> PlacementResult`; 06 reason list lacks `NO_PRESENCE`, `SPACING`, `NOT_VISIBLE`, `ENEMY_RADIUS`, `PREREQ`, `ELIMINATED`; 04 V-BLD checks "cell within a friendly build radius", which rejects every valid Outpost (02 AR-1).
- `class_name` collisions (Godot class names are global): `CommandValidator` in 03 s3.5 (sim) and 04 s11.3 (`server/command_validator.gd`); `MatchRules` in 02 s12.1 (`src/sim/match_rules.gd`, phase API), 03 s15.4 (sim, mode/caps/debug flags) and 04 s9.3 (`server/match_rules.gd`, JSON schema `match_rules.schema.json`, which 02 also claims for its def).
- Phase enums: 02 `LOADING, PLAYING, EXPOSURE, ENDED`; 03 `OPEN/EXPAND/SIEGE/OVERTIME/ENDED`; 05 `OPEN|EXPAND|SIEGE|OVERTIME`; 04 `LOBBY, LOADING, COUNTDOWN, PLAYING, ENDED`.
- Command builders: 03 `Command.pilot(player, tick, input)` vs 04 `Command.pilot_input(slot, entity, input)`. 04 uses `Sphere.interest_cell(p)` / `cell_centre_on_datum(cell)`; 03 provides `cell_of(d, n)` / `cell_center_dir(cell, n)`. `NetSimView.sample(alpha)` (03) vs `sample(render_tick)` (04).

**Required fix.**
1. `step_ship` = 03 s5.2 form; 03's AR-1 covers it as a MODULE.md refinement of 01 s9.4; 04 s5.3 pseudocode rewritten to `Kinematics.step_ship(s, _inputs.get(t), _def, _rules, _terrain, Sim.DT)`.
2. `Build.can_place(player: int, def_id: int, cell: int, rotation: int) -> Build.Reject` with 02's 13 reasons (03 s15.4 rewritten; `CommandResult.REJECTED_PLACEMENT` carries the `Reject` value in its payload); 06 s7.3 calls this signature on the client's `LocalSimView`/terrain mirror and its reason priority list adds the six missing reasons and the Outpost presence ring; 04 V-BLD drops its own radius check and defers to `Build.can_place`.
3. Rename 04's `CommandValidator` to `ProtocolValidator` (`server/protocol_validator.gd`). One `MatchRules` class in `sim/match_rules.gd` = 03's config fields + 02's phase API; 02's def file becomes `match_rules.json`/`MatchRulesDef` (content); 04's allocation payload type becomes `MatchConfig` (`server/match_config.gd`, schema `match_config.schema.json`).
4. Two enums, named differently: `MatchRules.Phase { LOADING, PLAYING, EXPOSURE, ENDED }` (rules state, 02) and `MatchArc { OPEN, EXPAND, SIEGE, OVERTIME }` (clock band, 03 `match_phase()` renamed `match_arc()`; 05 uses it); 04 `ServerSession` lifecycle phase stays as is but is named `SessionPhase`.
5. 04 uses `Command.pilot(...)` and `Sphere.cell_of(p, Sphere.GRID_INTEREST)` / `Sphere.cell_center_dir(cell, Sphere.GRID_INTEREST) * Sphere.PLANET_RADIUS`; `NetSimView.sample(render_tick: float)` in both docs.

### C2-13 (major) Bot difficulty numbers: 02 promises and 05 profiles disagree, and live in two files

**Problem.** 02 s15 (`bot_promises.json`): think 3/1/1/1 s, reaction +6/+2/+0.5/0 s, command cap 20/40/80/150 per min, tier ladder Normal>Easy 80-97 %, Hard>Normal 70-90 %, Brutal>Hard 60-85 %, doctrine pairings 42-58 %, first Outpost <= 6:00 (Normal). 05 s7.8 (`bot_profiles.json`): think 3/2/1/1 s, reaction 8/4/2/0.5 s, 15/30/60/120 per min; 05 s11.3 requires each tier >= 70 % (fails 02's 60-85 % Brutal band at 60-69 %), doctrines 40-60 %; SC-41 accepts first Outpost by 6:30; SC-42 asserts Easy <= 15/min. 03 s9.2 adds a third file `bots.json`.

**Required fix.** 02 owns the promises, 05 the mechanism. 05 s7.8 table values set to 02's: `think_period_ticks` 90/30/30/30, `reaction_delay_s` 6/2/0.5/0, `max_commands_per_min` 20/40/80/150; 05 SC-42 -> 20/min; SC-41 -> 6:00; 05 s11.3 tier ladder and doctrine rows replaced by "BAL-27 and BAL-10 bands of 02 s18.2". `bot_profiles.json` holds behaviour parameters only and references the tier id; the promise numbers are read from `bot_promises.json` (one source). 03 s9.2 `bots.json` row renamed `bot_profiles.json` (owner 05).

### C2-14 (major) Commander bot opening books cannot run on 02's start kit

**Problem.** 05 s14 assumes the start kit "Core + Refinery + Shipyard + Vehicle Bay + 1 Harvester"; 02 s8.1 fixes "Core, Refinery, 1 Harvester". None of the three books in 05 s7.3 builds a Shipyard or Vehicle Bay, yet every book's first steps `produce harvester`/`dart`; `bulwark_standard` builds a Hangar (02 prerequisites: Pad + Shipyard) with neither; the Outpost steps ignore the 02 AR-1 presence rule (a friendly unit within 300 m, >= 800 m from own Core). 02 s8.7/s8.8 already gives the Normal books that hit the checkpoints. SC-40/SC-41 would fail on day one.

**Required fix.** 05 s7.3 books are rewritten from 02 s8.7 (1v1 frontier book) and s8.8 (interior book): first steps `build solar_array`, `build shipyard`, `produce dart`, `build vehicle_bay`, `produce harvester`...; `bulwark_standard` adds `build pad` and `build shipyard` before `hangar`; every `build outpost` step is preceded by `{ "do": "order", "kind": "move", "unit": "dart|scout", "to": "<site>" }` and carries `"when": "presence"`. 05 s14 start-kit row replaced by 02's kit. `BuildPlanner.resolve_site()` enforces `min_spacing_friendly` 800 m and `min_spacing_enemy` 1,500 m.

### C2-15 (major) Tower targeting data duplicated with different values (02 vs 05)

**Problem.** 02 s4.4 `target_priority` = `bomber, hauler_loaded, lancer, dart, siege_crawler, harvester, scout, hauler`; 05 s6.8 base weights put all ground units (20) below scouts (30) and empty haulers (25). 05 uses Autocannon "0-400 m" and ignores 02 AR-2 `h_rel_min` -200 and Missile `target_agl_min` 40; 05 requires the lock cone "held 0.5 s" while 02 sets `lock_time_s` 1.0 (tower) / 0.8 (Lancer). 05 SC-30 "never targets a ship above 400 m" fits; SC-31 is consistent.

**Required fix.** 05 s6.8 reads order and envelopes from `towers.json` (`target_priority`, `h_rel_min`, `h_rel_max`, `target_agl_min`) and lock time from the weapon's `lock_time_s`; its utility formula keeps the multipliers but its base weights are derived from the priority list (100, 80, 60, 50, 40, 30, 25, 20 in 02's order). Delete "Autocannon 0-400 m, Flak >= 150 m" literals from 05 s6.8 and replace with "per towers.json envelopes (02 s4.4, incl. AR-2)". 05 s6.4 Lancer "lock cone holds 0.5 s" -> `lock_time_s`.

### C2-16 (major, partly 01) Matchmade queues, mode ids and bot-fill timing differ in 01, 02, 04 and 06

**Problem.** 01 s3.4 rates "1v1, 2v2, 3v3/4v4 pooled", but 01 s12 brief tells 02 "quick match 1v1/2v2, custom to 4v4". 02 s14 has `pvp_quick_1v1`, `pvp_quick_2v2` and no team queue; 04 s10.4 has `pvp_1v1`, `pvp_2v2`, `pvp_team` (3v3/4v4) and `coop`; FleetManager `mode` values are `pvp_1v1|pvp_2v2|pvp_4v4|coop|custom`. Bot fill: 02 says 1v1 fills after 120 s (flagged "vs bot", no MMR), 2v2 after 60 s; 04 fills only `pvp_team` after 90 s; 06 s8 shows `BOT_FILL_NOTICE` at 60 s. Quick-match doctrine pick: 02 OQ-12 blind pick until both lock; 04 allocation already carries `doctrine`; 06 s8 shows a "20 s doctrine window" after the match is found but before start; nobody says where that window runs (Nakama or the match process LOBBY phase).

**Required fix.**
1. Owner clarification of 01 s3.4 vs s12 (default: a matchmade `pvp_team` queue exists at launch, 3v3/4v4 pooled, hidden MMR).
2. One mode-id list used by 02 `modes.json`, 04 ticket `s_mode`, FleetManager `mode` and `MatchConfig.mode`: `pvp_1v1`, `pvp_2v2`, `pvp_team`, `coop`, `custom`, `skirmish`, `campaign`. 02 s14 adds a `pvp_team` row (humans 6-8, bots fill, hidden MMR team queue).
3. Bot fill: 1v1 120 s (flag vs-bot, no MMR change), 2v2 60 s (bot-filled matches weight 0.5), team 90 s; 04 s10.4 escalation text and 06 s8 `BOT_FILL_NOTICE` timing take these per-queue values from `modes.json`.
4. Doctrine pick runs in the match process `LOBBY` phase (04 s8): a new `DOCTRINE_PICK` command message (client -> server, ch0) and a `LOBBY_STATE` message (server -> client) carrying lock flags only (blind) for 20 s; 04 removes `doctrine` from the allocate request for quick match; 06 s8 lobby row references these messages.

### C2-17 (major) Match results and score do not carry what 02, 06 and 08 need

**Problem.** 02 s17 requires Pilot/Commander score split, medals, final structure value in results, and XP/level/cosmetic progression in Nakama. 04's `MATCH_END` per-player fields are `score, kills, deaths, structures_built, manual_landings`; the FleetManager result POST has the same; `match_history` and `match_result` RPC have no medals, split or structure value. 06 s8 results screen also shows "structures destroyed, sorties, ore mined, time piloted per class". 08 SL-1 needs `player_score` (banked, unbanked) replicated during the match. No doc specifies the in-match score stream (02 `scoring.json` events have no wire representation).

**Required fix.** 04 s2.3 `MATCH_END` and s9.3 result body gain per player: `score_pilot u32`, `score_commander u32`, `medals[] u8 ids` (02 `medals.json` order), `structures_destroyed u16`, `sorties u16`, `ore_mined u32`, `pilot_time_s[class] u16 x5`, plus `structure_value[team] u32`; `match_history` and the `match_result` RPC (XP per 02 s17.3, medal unlocks) store them. `TEAM_STATE` (or `TEAM_DETAIL`, C2-05) carries per-player score at 2 Hz. 02 GD-27 acceptance adds "MATCH_END carries every field above".

### C2-18 (major) Two landing-grade systems (02 S/A/B vs 08 ACE/CLEAN/FAIR/HARD)

**Problem.** 02 s17.1 grades S/A/B by thresholds (S <= 2 m/s, 4 m/s, 5 deg ...) with points 100/50/25 and x1.5 hot within 1,500 m; M1 requires "grade B+", medal `feather_touch` needs "A or better". 08 SL-1 grades by a weighted quality score into ACE/CLEAN/FAIR/HARD/BENT/CRASH/AUTO with points 50/30/15/5, x1.5 hot within 800 m, banking multipliers, and moves the x0.9 repair bonus to FAIR+. 06 s6.4 toasts "+ Manual landing" only. Both define `scoring.json` `landing_*` keys. FEAT-03/04 overlap GD-15/GD-27.

**Required fix.** Owner decides on adopting SL-1 (08 shortlist). Default until decided: 02's S/A/B system is v1 canonical; 08 SL-1 is rewritten as an extension that keeps 02's grade names and thresholds (S/A/B plus HARD for safe-but-below-B, BENT, CRASH, AUTO) and 02's points, and adds only banking; hot radius 1,500 m (02). Grades are carried by the `LANDING` event (C2-03), not by extra `DOCKED` fields. FEAT-03/FEAT-04 are merged into GD-15 (landing grade) and FEAT-05 depends on GD-27.

### C2-19 (major) Mission 1 / onboarding content contradicts between 02 and 06

**Problem.** 02 s16.2 M1 "Landfall": no enemies, 6 survey gates (boost gate, below-rim gate), climb to "uplink fading", auto-dock on the Core pad, then a manual landing at grade B+; guns and bombs are M2, possession of towers M3, building M4. 06 s12 says "Mission 1 is the onboarding session (02 owns content; 06 owns beats)" but its beats include 3 drone kills with guns, bombing a derelict crawler, a training rocket with flip, a harvester-under-attack alert, building an Autocannon and a Solar Array, queuing a Harvester and possessing an Autocannon against two raiding Darts. 06 also gives M2-M3 different teaching content ("ice, Haulers, power, hand-over"). GD-30 and UX-36 would build different missions.

**Required fix.** Decide which document's sequence holds; default: keep 01 Q4 "missions 1-3 are the tutorial" with 06's 15-minute first-session target, by moving 06 s12 beats 3:30-6:00 (guns, bombs, rocket/flip) to M2 and beats 10:00-13:30 (build, possess tower) to M3, so M1 = 02's Landfall plus 06's camera/release/commander-view beats (0:40-3:30, 6:00-10:00). 06 s12 table is split into M1/M2/M3 rows accordingly and its sentence on M2-M3 is replaced by a pointer to 02 s16.2; 02 s16.2 M1 adds "release and watch the Dart patrol; zoom to Commander view and jump to an alert" as objectives (`RELEASE`, `CLIMB_TO` exist; add objective kind `CAMERA_TIER` to 02 s16.3).

### C2-20 (major) Relay Station and moving-sun rules defined twice (02 vs 08), duplicate tasks

**Problem.** Relay capture: 02 s5.3 contest radius 300 m, progress resets if the Hauler leaves, recapture by the same rule, +300 score; 08 I-03 contest radius 600 m, progress decays 5 %/s, enemy-held stations must be neutralised (20 s) then captured (20 s). Moving sun: 02 M5 uses `cold_trap_sunlit_mult` 0.5 and the solar band 0.5 deg linear formula; 08 I-04 says sunlit traps stop yielding and buffers lose 2 % per 10 s, plus a +-3 deg twilight band at 50 %. Tasks GD-23/GD-33 and FEAT-33 implement both.

**Required fix.** 02 owns the numbers. If the owner adopts 08's refinements, 02 s5.3 and s8.4/s16 are revised once and 08 cites them; until then 02's rules stand and 08 I-03/I-04 are marked "proposal, not adopted". Delete FEAT-33 (or make it a 02-revision task "adopt I-04 into 02 and update GD-33"); GD-23 acceptance cites the chosen contest radius.

### C2-21 (major) Team colour, shape and allegiance model differ between 06 and 07

**Problem.** 06 A11Y-01 uses Okabe-Ito relation colours (ally #0072B2, enemy #D55E00, self #56B4E9, FFA extras) with shapes circle, diamond, triangle, square, hexagon, star, cross, chevron and requires CIEDE2000 >= 20 under each CVD simulation. 07 s2.2 uses per-player slot colours (Amber, Cobalt, Mint, Forest, Magenta, Orchid, Lime, Coral) with shapes circle, triangle, square, diamond, cross, star, chevron, ring, an allegiance frame (solid / brackets / dashed) and measured CVD minima of 12.0-13.6 (so 06's >= 20 threshold cannot pass with 07's palette). Emissives and UI tokens would diverge.

**Required fix.** 07 owns colour (01 s12 "07"). 06 A11Y-01 is rewritten: world emissives and markers use 07 s2.2 slot colours and shapes in 07's order; allegiance = 07's frame styles; thresholds = 07 s2.3 (team vs team >= 12 under any CVD, >= 25 normal; shape mandatory). 06's Okabe-Ito relation scheme becomes the A11Y-02 preset "Relation colours" (self/ally/enemy recolour of emissives and markers), which 07 mirrors as a palette variant in `palette.json` and re-checks with `cvd_check.py`.

### C2-23 (major) Missing sim and app pieces: Vision, weapon fire, ground motion, mode orchestration

**Problem.** No work seed in any doc implements: `sim/vision.gd` (03 s3.7: visible_mask, per-team interest lists, Sensor Mast deck reveal, 10 Hz stagger) although `net/Interest`, fog ghosts, bots and BAL metrics depend on it; the weapon-fire pipeline in `Combat` (rate of fire, bursts, cooldowns, ammo and supply-pool draw, projectile spawn, missile lock acquisition) beyond damage rules (GD-08) and tower envelopes (GD-09); `GroundMotion.step()` (03 s5.3; AI-16 is the sim_ai follower only); tether/tow physics for Haulers (01 s3.2 swing); `app` mode orchestration (offline in-process `ServerSession` + `ClientSession` over `LocalTransport`, Skirmish/Co-op/Campaign launch from setup screens, `app/match_controller.gd` that fills `AssistContext` and routes `pilot_input` (06 s2.2), pause/save/load wiring).

**Required fix.** Add seeds:
- TA-37 `sim/vision.gd` per 03 s3.7 (Opus; depends TA-14, TA-18; acceptance: horizon occlusion test vectors, Sensor Mast reveal, 10 Hz stagger, <= 1.1 ms p95 at S-SIM-1 scale).
- GD-36 weapon-fire pipeline in `sim/combat.gd` (Opus; depends GD-08, TA-14; acceptance: Dart fires 10 rounds/s and consumes ammo; tower burst 5 x 1.2 s; unsupplied tower 50 % rate; lock acquired after `lock_time_s`).
- TA-38 `sim/ground_motion.gd` (Sonnet; depends TA-13, TA-20; acceptance: 02 slope speed formula, snaps to terrain, path following on cube edges).
- GD-37 tow tether physics (Sonnet; depends GD-19; acceptance: damped pendulum, Foundry 2 tows, release on Hauler death).
- UX-39 `app/match_controller.gd` and offline session bootstrap for Skirmish, Co-op (listen host) and Campaign, incl. pause/save/load (Sonnet; depends NET-17, TA-21, UX-24; acceptance: each mode starts from its setup screen to PLAYING; save and load round-trip in Skirmish).

### C2-24 (major) Missing launch work: release pipeline, compliance artefacts, analytics, crash reporting, entitlements

**Problem.** Nothing seeds: `release.yml` (Android AAB signing, macOS notarisation, iOS signing via S-IOS-1, server Docker image build and push; 01 ADR-12) - TA-03 covers only PR/nightly; S-IOS-1 has no seed; `docs/compliance/` privacy manifest, Play data-safety form and App Store privacy answers (ADR-13 "maintained by the platform lane"); an analytics event taxonomy and pipeline (`platform/analytics.gd` is referenced by 04 s14 and 06 s12 `onboarding_step`, and 02 s18.4 playtest telemetry, but no event schema, sink, EU host or age-band gate is specified); client crash reporting (01 s9.2 `app` "crash reporting"; only `LEAVE(CRASH_REPORTED)` exists); entitlements and IAP on the client (Q2 default: mobile one-time unlock IAP; 04 has only a `receipt_validate` stub; no store-integration seed for Google Play Billing / StoreKit / Steam); Steam store build/depot upload.

**Required fix.** 04 adds: NET-40 analytics event schema (`tools/schemas/analytics_event.schema.json`: event name, pseudonymous id, session, platform, input class, payload) + Nakama `telemetry` RPC storage in an EU store + age-band gate (Sonnet); NET-41 crash report endpoint (FleetManager `POST /v1/crash` with log tail and build id, no PII) + `app` crash hook (Sonnet). 06 adds: UX-40 entitlements client (`platform/entitlements.gd` with Play Billing, StoreKit via export plugin decision, Steam DLC check in v1.1) and unlock UI (Sonnet, depends NET-32); UX-41 `docs/compliance/` privacy manifest, data-safety and App Privacy answers generated from the analytics schema (Haiku, Opus review). 03 adds: TA-39 `release.yml` with AAB, macOS, server Docker image, and TA-40 S-IOS-1 (Sonnet).

### C2-25 (major) Replay browser, spectator UI and save/load UI have no data source or spec

**Problem.** 06 s8 has a Replays screen and a replay viewer, but 04 stores replays only in server object storage (14 days) and specifies no RPC or signed URL for a client to list or download them (`match_history.replay_object` is a path the client cannot fetch); offline Skirmish replays are not recorded at all (ADR-10 says replays are server-recorded, and the offline `ServerSession` is a server). The Match screen has a `SPECTATING` state but no spectator HUD/camera spec (04 NET-26 is server-side only). Save/load: 06 shows only "Continue" (autosave); ADR-10 promises saves for Skirmish and Campaign, but no manual save/load or slot UI is specified.

**Required fix.** 04 s10.5 adds RPC `replay_url(match_id)` returning a 15-minute signed GET URL for matches in the caller's `match_history`; 04 s13 states offline sessions write `.pwr` to `user://replays/` (max 20 files, oldest deleted); 06 s8 Replays screen lists local files plus online history and downloads via the RPC; new seed NET-42 (Sonnet). 06 adds a spectator overlay row to s7 (follow target, free camera, player list, no HUD consumables) and a "Save / Load" pause-menu item for offline modes with 3 manual slots + autosave; seed UX-42 (Sonnet).

### C2-26 (major) Duplicate and overlapping work seeds; dependencies that name no ID

**Problem.** Same work in several docs: schemas/defs (GD-01..05 vs TA-07/TA-10 vs AI-19/UX-08/FEAT-01 schema parts), ContentDB (GD-06 vs TA-09), map recipes (GD-22 vs TA-16 vs ART-28..30), baker validation/preview (TA-15 vs ART-31), quality tiers (TA-31 vs UX-33 vs ART-19), docking/service (TA-19 vs GD-15 vs FEAT-04), soak harness and metrics (TA-34 vs GD-24 vs AI-31), moving sun (GD-33 vs FEAT-33), landing grade (GD-15/GD-27 vs FEAT-03/04), golden scenes (TA-35 vs UX-37 vs ART-33). Dependencies cite prose or non-existent prefixes: 04 uses "SIM `SimWorld`", "AI safety handoff", "03 `core/sphere.gd`", and its header defines prefixes `SIM`, `PLT`, `OPS` that no doc uses; 05 AI-03 "sim MODULE.md", AI-07 "Terrain.height_at"; 07 ART-28/ART-31 "03 baker"; 08 FEAT-04 "03 docking", FEAT-17 "05 steering"; 02 GD-24 "05 Commander bot", GD-29 "new SimEvent kinds (03)"; 06 UX-17 "03 Kinematics", UX-21 "03 Build.can_place". ID prefixes themselves are unique (GD, TA, NET, AI, UX, ART, FEAT) and no ID is duplicated.

**Required fix.** Apply this mapping (each doc edits its own rows):

| Keep | Merge into it / delete | Note |
|---|---|---|
| GD-01..GD-05 | TA-07 (except rules + map_recipe schemas), TA-10 (except `rules.json`), schema parts of AI-19, UX-08, FEAT-01 stay with their docs but follow GD-01 conventions | C2-01 |
| TA-09 | GD-06 | |
| TA-15 | ART-31 | C2-02 |
| ART-28/29/30 (terrain) + GD-22 (resources) | TA-16 becomes test maps only | C2-02 |
| TA-31 (tier system) | UX-33 keeps mobile pause/resume/haptics only; ART-19 supplies knobs to TA-31 | |
| GD-15 (service + grade) | TA-19 drops "docking service"; FEAT-03/04 merged | C2-18 |
| GD-24 (BalanceProbe, configs) | TA-34 = harness scene only; AI-31 = AI metrics added to GD-24 output | |
| GD-33 | FEAT-33 | C2-20 |
| TA-35 (12 world goldens) | UX-37 UI goldens and ART-33 art goldens under the extended A3 set (C2-30) | |

Dependency rewrites: 04 "SIM SimWorld" -> TA-18, "SIM SimView" -> TA-18, "03 core/sphere.gd cell functions" -> TA-04, "AI safety handoff" -> AI-08, "03 Kinematics.step_ship" -> TA-12; delete the `SIM/PLT/OPS` prefix sentence in 04 s19. 05 AI-03 -> TA-06, AI-07 -> TA-13, AI-10 "04 prediction" -> NET-18, AI-16 "S-NAV-1" -> TA-20. 07 ART-28, ART-31 -> TA-15. 08 FEAT-04 -> GD-15, FEAT-09 -> AI-11, FEAT-13 "03 attacker ids" -> TA-18, FEAT-17 -> AI-05, AI-07, FEAT-25 -> ART-28, FEAT-28 -> NET-10. 02 GD-24 -> AI-27, GD-29 -> TA-18, GD-30 "06 tutorial UI" -> UX-36, GD-31 "05 bot" -> AI-23, GD-35 -> UX-19, NET-40. 06 UX-17 -> TA-12, UX-18 "03 accessors" -> TA-18, UX-19 "04 events" -> NET-10, UX-20 "05 order names" -> AI-01, UX-21 -> GD-16, UX-26 "04" -> NET-36, UX-35 "04 platform APIs" -> NET-32, UX-36 "campaign runtime" -> GD-29.

---

## Part B. Minor findings

### C2-27 (minor) Production queue length and command rate limits disagree
02 s6.4 `queue_max` 5; 03 s3.2 side table "<= 16 per structure"; 04 V-PRD "queue length <= 10". Command rate: 03 S10 "<= 30 commands per player per second"; 04 s11.4 "10/s sustained, burst 30". **Fix:** queue max 5 (02) in 03 s3.2 and 04 V-PRD/s18; command rate is 04's token bucket (10/s, burst 30) and 03 S10 cites it.

### C2-28 (minor) Camera near plane and touch emulation settings differ (03 vs 06)
03 s7.6 `near = clamp(0.3 + 0.004 * h_cam, 0.3, 20)` for all tiers and asks 06 to apply it; 06 s5.5 fixes Chase at 0.3 m and orbit at `clamp(4 + (A_g - 300) * 16 / 2200, 4, 20)`. 03 s1.1 `emulate_mouse_from_touch=false`; 06 s16 assumes `true`. **Fix:** 06 s5.5 `NearFarPolicy` default implements 03's formula (06's orbit formula kept as a named alternative S-WORLD-1 may choose); `emulate_mouse_from_touch=false` (06 mappers already ignore emulated events; 06 s16 line deleted).

### C2-29 (minor) Quality tier naming, benchmark and knob values differ
03 s13 tiers Low/Mid/High, 2 s micro-benchmark, LOD `threshold_pixels` 2.0, shadows High 2,048/1,500 m; 06 s9.3 LOW/MEDIUM/HIGH, 5 s benchmark with p90 thresholds; 07 s4.6 `threshold_pixels` 1.0 PC / 3.0 mobile, s1.5 shadows max 800 m, PC-High only. **Fix:** names LOW/MEDIUM/HIGH; one benchmark (03's 2 s run inside 06's pre-warm window, 06's p90 rule as the decision); 03 s13 table takes 07's `threshold_pixels` and shadow distance; 03 s1.1 default `threshold_pixels` stays 2.0 until the tier applies.

### C2-30 (minor) Golden screenshot scene count exceeds ADR-11's 12
03 TA-35 already uses 12 (Z-plan plus night readability); 06 A3 asks for up to 8 UI scenes; 07 ART-33 adds 6 art goldens. **Fix:** extend 06's A3 request to "up to 8 UI and 8 art/night scenes in `godot/test/golden/ui/` and `golden/art/`"; 03 TA-35 drops its night-readability scenes in favour of 06's A11Y-16 pair.

### C2-31 (minor) Small art-vs-design mismatches
Smoke thresholds 02 0.75/0.5/0.25 vs 07 s6 66 %/33 %; structure base: 03 s7.6 plate 0.6 m below / 1.5 m beyond vs 07 s4.2 foundation depth `0.27 x half_footprint`; Earth: 03 s7.8 `normalize(-POLE_AXIS + 0.3 PRIME_AXIS)` vs 07 s1.5 exactly -Z, 6 deg; atlas: 03 s9.3 2,048^2 vs 07 256^2; 07 s1.2 `footprint_cells = ceil(m / 6.5)` but 03 s2.7 gives 8.68 m corner cells, and the Rail Lance mesh (39 m) overhangs 02's 4x4 footprint (34.7 m at corners). **Fix:** 07 s6 smoke states at 02's three thresholds; 03 s7.6 accepts 07's foundation rule (depth >= 0.6 m) and drops its own numbers; Earth at -Z (07); 03 s9.3 atlas 256^2; 07 s1.2 divisor 8.68 m (03 s2.7); 02 s5.2 Rail Lance footprint 4x5.

### C2-32 (minor) Audio and font budgets differ
03 s11.2 `audio.pck` ~25 MB raw / ~20 MB Brotli and 120 MB decoded web audio; 07 s8.3 music pack <= 4 MB, SFX <= 5 MB decoded. 06 s11 "one OFL UI family"; 07 s7 Rajdhani + Inter. 02 s21 asks 07 for "VO for 8 missions and 3 characters"; 07 s8.2 says text plus synthetic blips, no human VO. **Fix:** 03 s11.2/s11.3 use 07's figures (music pack <= 4 MB, web audio decoded <= 40 MB); 06 s11 says "two OFL families (07 s7)"; 02 s21 row 07 and 06 A11Y-08 say "campaign dialogue is subtitled text with speaker blips in v1".

### C2-33 (minor) Localisation file formats and key conventions differ
06 s11 canonical CSV per domain -> PO, keys `unit.<def_id>.name` derived by convention, domain `campaign_mNN`; 02 s1.2 puts `name_key` in every def and uses keys `campaign.m05.title`; 08 SL-3 stores barks in `content/locale/barks.en.json`/`barks.fi.json`. **Fix:** 06's pipeline is canonical; 02 drops `name_key` (derived) and renames campaign keys to `campaign_m05.title`; 08 barks become CSV domain `barks` (`barks.<key>.<variant>`).

### C2-34 (minor) Content-hash scope is unclear for UI and presentation files
03 s9.2 hashes "every gameplay def file (not locale, not presentation-only files)"; 06 puts fairness assists in `content/defs/assists.json` (in hash) and UI data in `content/ui/` (out); 07 puts `sfx.json` in `content/defs/` and presentation blocks inside gameplay defs. **Fix:** 03 s9.2 lists the hash inputs explicitly: all `content/defs/*.json` except `sfx.json`, `vfx_prewarm.json` and the `presentation` key of every def (stripped before hashing); `content/ui/**` and `content/locale/**` excluded; `assists.json` included.

### C2-35 (minor) 04 codec ranges do not fit 02's numbers
Velocity i8 at 2 m/s covers +-254 m/s but flak shells (300 m/s) are replicated as entities; `HIT` damage u8 cannot carry 400 (bomb vs ground) or Vanguard/Bulwark-resolved values; `ROSTER_REMOVE` has no reason byte although 06 s7.4 needs OUT_OF_VISION vs DEATH; the pilot block has an undefined `heat` byte and no rocket count. **Fix:** flak shells and rail slugs go out as `PROJECTILE_BATCH` spawns (ballistic, deterministic) like gun slugs; `HIT.damage` u16 (event 10 B); `ROSTER_REMOVE` entries `(index u16, reason u8)`; pilot block per C2-05.

### C2-36 (minor) Settings persistence has two homes
06 s8 persists settings to `user://settings/settings.cfg` via `app/settings_store.gd` and calls the model `core/config.gd` (`Config`); 03 s15.2 `Config` is a static reader of project settings and flags; 04 s10.3 stores `settings.client` in Nakama. **Fix:** 06 renames its model `SettingsModel` (`app/settings_model.gd`); local file is the source; signed-in clients sync `settings.client` on change (last-write-wins by timestamp), guests never sync; 04 s10.3 notes this.

### C2-37 (minor) Pad landing radius has no owner
03 s6.4 hard-codes 8 m (Pad), 10 m (Hangar), 12 m (Core); 08 SL-1 asks 02 for `pad_radius_m` (example 12); 07 Pad slab is 26 m. **Fix:** 02 s5.1 adds `pad_radius_m` to every pad-bearing def (Core 12, Outpost 10, Pad 10, Hangar 10, Relay Station 12); 03 s6.4 reads it.

### C2-38 (minor) Smaller 05 inconsistencies
05 s8 still says "assumed TOGGLE_ADJUTANT payload on TOGGLE_AUTO_REPLENISH" next to its own AR-1; 05 s7.2 bot think stagger `(tick + 4k) % period` vs 03 s4.2 `tick % 30 == b * 3`; 05 Commander slice 3 x 0.7 ms vs 03's 1.5 ms single think. **Fix:** delete the TOGGLE sentence (C2-03); 03 s4.2 adopts 05's slicing (3 slices <= 0.7 ms, stagger `(tick + 4k) % period`) and updates the "Commander think" budget row.

### C2-39 (minor) Quick-ping wheel content differs (04 vs 06)
04 `QUICK_PING.kind`: ATTACK_HERE, DEFEND_HERE, ENEMY_SPOTTED, NEED_HELP, ON_MY_WAY, ACK; 06 s9.5: attack here, defend here, need escort, enemy bombers, on my way, need ice, thanks, retreat (08 adds "Need supply"). **Fix:** 04's kind enum becomes 06's eight entries in 06's order (+ NEED_SUPPLY reserved for SL-5); the canonical list lives in 06 `content/ui/pings.json`, 04 cites it.

### C2-40 (minor) Small 04/03 phase-name and lifecycle wording
04 s8 lifecycle and 02 s12.1 state diagram both own "Loading -> Playing" transitions with different timeouts (02: "all clients loaded or 60 s"; 04: LOBBY 60 s join window, LOADING 60 s, COUNTDOWN 5 s). **Fix:** 02 s12.1 diagram starts at `PLAYING` and references 04 s8 for pre-match phases; `Loading` removed from 02's `Phase` enum (C2-12).

### C2-22 (minor) 08's shortlisted verbs are bound to keys 06 already uses

08 SL-2/SL-4 bindings collide with 06 s3.1: gamepad D-pad Up (06: ping wheel hold) for Form on Me; D-pad Down (06: Release) for Mark; pointer F (06: auto-dock hold in Chase, Quick Fly in Tactical) for Form; pointer R (06: Release) for Mark; the touch wing icon and REC button are absent from the 06 s4.3 layout. Every gamepad button is already used in 06's Chase map. **Fix (applies only if the owner adopts SL-2/SL-4):** Form on me, Attack my target and Release wing become three entries of the ping wheel (06 s9.5; works on all three input classes without new buttons); Mark = gamepad View hold 0.5 s (tap stays peek), pointer `M`, touch a REC button in the amber zone of 06 s4.3 with explicit coordinates; 08 SL-2/SL-4 "UI (06)" paragraphs cite 06 s3.1 instead of naming keys.

---

## Part C. Completeness against the vision and the four launch modes

| Need | Online PvP | Skirmish | Co-op | Campaign | Status / issue |
|---|---|---|---|---|---|
| Rules, stats, economy | 02 | 02 | 02 | 02 | covered (schema conflict C2-01) |
| Match start: queue, lobby, doctrine pick | 04, 06 | 06 setup | 06 setup, 04 `coop` ticket | 06 briefing | doctrine-pick flow missing for quick match (C2-16) |
| Bot fill-in | 04/05 | 05 | 05 (allies and enemies) | 02 mission bots | timings inconsistent (C2-16); campaign bot `script` hook (02 s16.3 `"script": "m05_marrow_dusk"`) has no counterpart in 05: add a `ScriptedDirector` hook to 05 s7 that runs mission scripts as command sources (folded into C2-14 revision of 05) |
| Disconnect / reconnect / caretaker | 04, 05 | n/a | 04, 05 | n/a | covered (rules conflict C2-08) |
| Save / load | n/a | ADR-10 | listen host | ADR-10 | UI missing (C2-25) |
| Results, score, medals, XP | 04, 06 | 06 | 06 | 02 medals | payload missing (C2-17) |
| Replays, spectators | 04 | offline replays unspecified | 04 | n/a | C2-25 |
| Tutorial hooks | | | | 02, 06 | conflict (C2-19); objective panel widget not in 06 s6-s7 inventory: add "Mission objectives" widget (MissionRuntime.objective_states) to 06 s7.1 |
| Localisation of campaign text | | | | 02 GD-32, 06 s11 | format conflict (C2-33) |
| Accessibility in campaign | | | | 06 A11Y | subtitles and 75 % speed cover it |
| Settings persistence | 06 | 06 | 06 | 06 | C2-36 |
| Analytics, crash reporting | missing | missing | missing | missing | C2-24 |
| Anti-cheat | 04 s11.5 | n/a | 04 | n/a | covered |
| Entitlements / IAP (Q2 default) | | mobile unlock | | chapter 1 free | missing (C2-24) |
| Store compliance artefacts | | | | | missing (C2-24) |
| Release builds (AAB, iOS, macOS, server image) | | | | | missing (C2-24) |

---

## Part D. Work-breakdown audit

- **Prefixes and duplicates.** GD (02, 35 seeds), TA (03, 36), NET (04, 38), AI (05, 33), UX (06, 38), ART (07, 36), FEAT (08, 35). No duplicate IDs; no prefix collision.
- **Dangling dependencies.** None point to a non-existent ID, but about 30 dependencies are prose ("03 baker", "SIM SimWorld", "05 Commander bot"); C2-26 gives the replacement IDs. 04's header mentions prefixes `SIM`, `PLT`, `OPS` that no doc defines.
- **Overlaps.** Ten clusters of overlapping seeds; C2-26 gives the merge table.
- **Gaps.** Vision, weapon fire, ground motion, tether physics, app orchestration (C2-23); release pipeline, iOS, compliance artefacts, analytics, crash reporting, entitlements (C2-24); replay download and spectator/save UI (C2-25); TEAM_DETAIL replication (C2-05); objective panel widget (Part C).
- **New seeds requested by this review:** TA-37, TA-38, TA-39, TA-40, GD-36, GD-37, NET-39, NET-40, NET-41, NET-42, UX-39, UX-40, UX-41, UX-42 (definitions in C2-05, C2-23, C2-24, C2-25).

---

## ADR amendment requests (escalations to the owner raised by this review)

| ID | 01 decision | Problem | Proposed change | Impact |
|---|---|---|---|---|
| C2-AR-1 | 01 s3.1.4 "pitch within 25 degrees of the pad normal" | Read as level (03) and as tail-down (05); CF thrust-only-forward physics favours tail-down | State "body forward (thrust) axis within 25 degrees of the pad normal: a tail-down powered landing" | 03 s6.4, 02 s17.1, 06 s6.4, 07 ship recipes (C2-10) |
| C2-AR-2 | 01 s9.2 dependency table | `input`/`ui`/`campaign` need sim contract types; 06 A1 and 08 already depend on it | Accept 06 A1 extended per C2-04 item 1 | `tools/deps.json` only |
| C2-AR-3 | 01 s3.4 ("3v3/4v4 pooled" rating) vs 01 s12 brief 02 ("quick match 1v1/2v2, custom to 4v4") | Two readings of whether a matchmade team queue exists | Confirm a `pvp_team` queue (3v3/4v4 pooled) at launch | 02 s14, 04 s10.4, 06 s8 (C2-16) |
| C2-AR-4 | 01 s9.4 enum lists | Kinds grow in five docs | Accept 03 AR-1 (append-only growth is a MODULE.md change) with the consolidated list of C2-03 | 03, 04 codec |

## Open questions (with defaults)

| # | Question | Default |
|---|---|---|
| CQ-1 | Adopt 08's shortlist SL-1 (banking) on top of 02's landing grades? | Keep 02 grades; banking optional pending owner (C2-18). |
| CQ-2 | Is Glassfield kept as a fourth (v1.x) map? | Yes, v1.x, after the three 02 maps ship. |
| CQ-3 | Should offline Skirmish record replays by default? | Yes, local `.pwr`, 20-file cap. |

## Cross-doc dependencies of this review

Every fix above edits only the doc named in its issue; where a fix needs another doc's decision (C2-10, C2-16, C2-18, C2-19, C2-20) the default stated in the issue applies until the owner answers.
