# 01 - Vision and Core Decisions

| | |
|---|---|
| **Project** | Codename **PLANEWAR** - arcade spaceship combat + base-building RTS on a spherical moon. Godot 4.7.2. Mobile, PC, browser. |
| **Document** | The spine. Every decision here is binding for docs 02-08 and for implementation agents. |
| **Status** | **v1.1, amended 2026-10-10** by the chief architect / integrator agent after the stage-2 critic reviews (C1-C3) and the owner's decisions; v1.0 written 2026-10-09. Inputs: `docs/research/R1-game-references.md`, `R2-godot-tech.md`, `R3-platform-requirements.md`; `docs/reviews/R0-resolution-register.md` (the binding resolution register; its Part B contract tables override 02-08). Every change is listed in the Amendment log at the end. |
| **Change policy** | Downstream docs may *refine* a number inside the tolerance stated here; they may not *contradict* a decision. A contradiction is raised as an "ADR amendment request" to the owner, not silently resolved. Enumerations, def field names, map ids, module dependencies and signatures are frozen in R0 Part B and `MODULE.md` files; they grow by appending, never by ADR. |
| **Units** | 1 Godot unit = 1 metre. Seconds, m/s, m/s^2 throughout. "R" = moon datum radius. |

**How to read.** Sections 0-6 are design (what the game is). Section 7 holds the technical ADRs (how it is built). Sections 8-9 are budgets and the module map that becomes the parallel work lanes. Section 10 fixes vocabulary. Section 11 lists the few genuine owner questions, each with a default so work continues. Section 12 briefs docs 02-08.

**Evidence convention.** Research facts cite R1/R2/R3 by section (e.g. "R2 s3.4"). Numbers marked *(anchor)* are tuning anchors that 02 may move within the stated tolerance after prototyping; numbers without that mark are hard constraints.

---

## 0. Working title, codename, pitch

### 0.1 Codename

**PLANEWAR** is the internal codename (it is already the repository and folder name). It appears in code, docs, CI and package IDs during development only. It never appears in store listings, marketing, the main menu or shipped package identifiers: R1 s1.4 and R3 s6.7 flag that any "plane"-adjacent name echoes the Triplane Turmoil trademark and the working title has not been cleared. The shipped bundle ID is reserved as `fi.<company>.<finaltitle>` and is set the day the title is chosen.

### 0.2 Title options for the owner

| Option | Why it fits | Clearance / risk note |
|---|---|---|
| **Regolith** | Lunar surface dust; short; sounds like a place and a material; the dust is literally what you fight over (ore is mined from it). | Common word; check EUIPO/USPTO class 9/41 for games with this exact title. Leading candidate. |
| **Earthshine** | The dim blue light that lights our night hemisphere; distinctive, pretty, and names a real mechanic in the game (the terminator). | Probably clear in games; the word is used by astronomy products. |
| **Dustline** | The terminator line drawn across the dust; also "the front line". Punchy, one word, easy to say in Finnish and English. | Likely clear; check for apparel brands. |
| **Low Moon** | References the low-orbit ceiling and the small moon; two short words; good for a logo. | Generic words, hard to protect but easy to clear. |
| **Mascon** | Lunar mass concentrations (real selenology); unusual, technical, ownable. | Obscure; check for company names. |

Default until the owner decides: the codename. All downstream docs write "the game" or "PLANEWAR".

### 0.3 Elevator pitch

PLANEWAR is an arcade dogfighting game fused with a Command & Conquer-style base builder, fought across the entire surface of a small moon. Every ship, turret and harvester on your side runs itself, and you can jump into any of them at any moment: fly a sortie, land on your pad to refuel and rearm, then zoom out to orbit and run the war. Two to eight players, bots that fill every empty seat, and one build that plays on phones, PCs and in a browser.

### 0.4 A match in eight sentences

You spawn in the commander view above your Command Core on the terminator line: daylight and solar power to the north, darkness and ice to the south. You queue two Harvesters and a Dart, drop a Solar Array and an Autocannon, then possess the Dart as it rolls off the Shipyard pad and climb out toward the enemy base 45 degrees around the globe. Below the horizon you see nothing; you fly low over a mare to stay hidden, pop over a crater rim and find their Harvester line. Two bombs, one Harvester dead, a Flak Battery wakes up and you dive away gaining speed, guns rattling at an intercepting Dart whose damage rolls are kind to you today. Fuel at twenty percent, you release control; the autopilot takes it home while you zoom out, see an alert that your southern Ice Extractor is under attack, and possess the Flak Battery there to pick the bomber off manually. Your Dart lands itself, you watch the resupply bars fill, and you take it back up with a Hauler of ice in tow. Twenty minutes in, the enemy's Core is exposed; your team's bombers, two of them human-flown, make the run while the Shield Projector you overbuilt holds your own Core together. Rematch.

---

## 1. Design pillars

Five pillars. Every feature proposal in 02-08 must name the pillar it serves; a feature that serves none is cut.

### P1. Possess anything, depend on nothing

- **This means:** every entity that can act has a competent autopilot (R1 s3 item 3: "the automatic layer is the product"). Taking control is one input, releasing is one input, and a released unit resumes its standing order, never idles. There is no avatar; a player whose ship dies is offered the nearest friendly unit (R1 s3 item 2). The player may ignore the RTS layer entirely and just fly, or ignore flying entirely and just command; both are complete ways to play.
- **This does not mean:** a hero unit, stat bonuses for possessed units (a possessed Dart is the same Dart with a human brain), units that wait for orders, or autopilots that are allowed to be stupid "because the player can take over" (Carrier Command's failure, R1 s2.2).

### P2. Momentum, gravity and the landing

- **This means:** thrust-vector flight with real inertia; constant gravity toward the core; dives gain speed and climbs lose it; finite fuel, ammo and bombs; a landing you must actually fly; two kill speeds (variable gun damage, instant-kill bombs) exactly as in the Sopwith/Triplane lineage (R1 s1.3). The resupply landing is the signature moment (R1 s3 item 9).
- **This does not mean:** orbital mechanics, Newtonian drift-forever, flight-sim controls, or punishing novices: assists exist per input class (Section 3.1.6) and a soft landing is learnable in the first campaign mission.

### P3. One moon, no edges

- **This means:** the whole sphere is playable; the horizon hides low flyers at about 1.1 km from 100 m up; the shortest route is a great circle and the antipode is three minutes away; the day and night hemispheres hold different resources; the two poles are neutral objectives equidistant from every base.
- **This does not mean:** multiple planets, orbit as a playspace (the ceiling is a wall, Section 5.3), or a flat map wrapped around a ball with seams.

### P4. Readable from cockpit to orbit

- **This means:** flat-shaded low-poly art with strong silhouettes; team colours that are emissive, colour-blind-safe and paired with shape cues; a HUD and alert system that always tells you where the fight is (R1 s2.1 AVOID list); picture-in-picture for the home base; one visual target (the Compatibility renderer) on every platform so no platform sees something another cannot.
- **This does not mean:** photorealism, effects that hide gameplay, or anything gameplay-relevant that only renders on a high-end GPU.

### P5. Fair, finite, rematch-ready

- **This means:** 20-30 minute matches with a hard ending; no pay-to-win and no gameplay unlocks in PvP; input-class matchmaking (R3 s5); bots fill every empty seat so queues work at low population; server authority against cheating; identical balance data on every platform.
- **This does not mean:** persistent wars, grind-gated units, platform-exclusive advantages, or ranked modes with asymmetric information between phone and PC players.

**Development principle (not a design pillar): everything is data, every module has a contract.** All balance in JSON, all module boundaries in `MODULE.md` files, so that Haiku-tier agents can tune and Sonnet-tier agents can build against specs without reading the whole codebase (Section 9, ADR-09, ADR-14).

---

## 2. Owner-confirmed decisions (restated)

| # | Decision | Interpretation used in this document |
|---|---|---|
| O1 | Spiritual successor to Triplane Turmoil with spaceships on a moon. | Mechanics inspired (land-to-resupply, gun vs bomb, ceiling, ground-defence altitude counters); zero Triplane code, assets, names or fiction (R1 s1.4). |
| O2 | Internet multiplayer. | Server-authoritative dedicated servers; browser clients must work (ADR-07). |
| O3 | Base building, gun towers, resource gathering, manufacturing (C&C-like). | Harvest -> refine -> manufacture -> build/defend loop; power gating; build radius; production from any camera (Section 3.2). |
| O4 | No player avatar; player can control anything; everything returns to automatic when not controlled. | Per-entity state AUTO / ORDERED / POSSESSED (Section 4). |
| O5 | Map much bigger in every direction; round moon; very large sphere with lunar texture. | R = 6,000 m sphere (**confirmed by the owner 2026-10-10**), full 3D shell to 2,000 m (Section 5). "Very large" is relative to a 12 m ship: the antipode is 171 s away at cruise; 1v1 bases sit 90 degrees apart (Section 5.7). |
| O6 | 3D globe with free flight; gravity toward the core; soft altitude ceiling at low orbit; chase camera on the possessed unit; zoom out to an orbital commander view. | Section 3.1, 4, 5.3. |
| O7 | 2-8 players, 1v1 to 4v4; AI bots fill empty slots. | Equal teams in matchmade play; FFA only in custom lobbies (Open question Q12). |
| O8 | First-release modes: Online PvP, Skirmish vs AI, Co-op vs AI, Story campaign. | Section 3.3.4. Campaign doubles as the tutorial. |
| O9 | Stylized low-poly, flat-shaded, strong team colours on a grey moon; much of it procedural. | ADR-02 (Compatibility renderer), 07 brief. |
| O10 | Mobile and PC first-class; browser "easily adapted". | GDScript only, Compatibility renderer, single-threaded web export, WebSocket transport, 20 MB initial web download (ADR-01, 02, 07; Section 8). **v1.0 ships Windows (Steam, incl. Steam Deck), Android (Google Play) and web (itch.io + own site); iOS, macOS, Linux native, Poki and CrazyGames are v1.1** (ADR-12). |
| O11 | Great new feature ideas welcome. | 08 brief; several are seeded in Sections 5-6 (poles as objectives, wreck towing, Adjutant). |

---

## 3. Core loops

### 3.1 Moment to moment: flight and combat

#### 3.1.1 Kinematic model: "curved-flat" (CF) flight

The sphere must *feel* like Triplane's flat world locally while being a real globe. Honest Newtonian gravity on a 6 km moon produces orbital lift: at 134 m/s a ship would never fall, and a released bomb would float beside it. That kills pillar P2. We therefore use an arcade model, implemented once in `sim/kinematics.gd` and shared by server and client prediction:

1. Each entity stores position `p` (moon-centred), velocity `v`, and orientation basis `B` (forward, up, right), all float32 (ADR-03).
2. Each tick, after integrating `p += v * dt`, the local up vector changes from `n = normalize(p_old)` to `n' = normalize(p_new)`. We rotate `v` and `B` by the minimal rotation that maps `n` to `n'` (parallel transport along the great circle). Horizontal stays horizontal; a ship flying level follows the curve of the moon without pilot input. **Transport applies to ships, bombs, siege shells and guided rockets. Gun slugs, flak shells and rail slugs are not transported: they fly straight lines in the world frame (item 3.1.3), so what you aim at is what you hit** (R0 C1-03).
3. Gravity is a constant `g = 6.0 m/s^2` toward the core, applied to `v` every tick. No altitude falloff, no orbital term, no atmosphere.
4. Thrust acts along the body forward axis with magnitude `a_thrust * eff(v_fwd)`, where `eff` is 1.0 up to 80 percent of the ship's rated cruise speed and falls linearly to 0.0 at cruise, giving a soft forward speed cap. Gravity is not capped, so dives exceed cruise (hard structural cap at `v_dive_max`; beyond it the hull takes damage per second).
5. Body-frame velocity components are damped so ships "grip" their heading like aircraft: sideways (right axis) at `k_side` (Dart 0.5 /s), vertical (body up axis) at `k_up_eff`, forward not at all (momentum carries). **The vertical grip scales with forward speed so that level cruise needs only a few degrees of nose-up** (R0 C1-04): `k_up_eff = k_up + (k_up_flight - k_up) * clamp(v_fwd / v_cruise, 0, 1)^2`, with per-ship `k_up` (Dart 0.1 /s, the glide value) and `k_up_flight` (Dart 1.0 /s, anchor 0.6-1.5); `rules.lift_model` selects `speed_scaled` (default) or `damping_only` for the S-FLIGHT-1 A/B. At zero forward speed the model is unchanged: free fall is nearly undamped (terminal sink rate 60 m/s) and a Dart with engines cut at 100 m hits the ground in about 6 s. Projectiles have no damping.
6. Pitch, yaw and roll are rate-limited angular velocities with per-ship caps; the "flip" (180 degree roll-and-pitch reversal in 0.5 s, Triplane's roll identity, R1 s3 item 8) is a discrete manoeuvre with a 2 s cooldown.
7. Retro-thrust ("brake") decelerates at `0.6 * a_thrust` and is the vacuum replacement for Triplane's Up+Down air brake.
8. Collision: entity bounding sphere vs analytic terrain height `Terrain.height_at(dir)` and vs other entities' spheres (ADR-05, ADR-06). Terrain impact above 25 m/s normal speed destroys a ship; 8-25 m/s damages it.

Why constant g = 6.0 rather than lunar 1.62: fall times. From 150 m a bomb ejected downward at 40 m/s lands in 3.1 s, and an engine-out ship from 300 m hits in 10 s; at 1.62 m/s^2 those are 6 s and 19 s and gravity stops mattering. The fiction is "a dense little moon"; 07 may invent a reason or leave it unexplained. *(anchor: 5.0-8.0)*

#### 3.1.2 Pilot inputs

A possessed ship receives one `PilotInput` per sim tick (Section 9.4): thrust 0..1, pitch -1..1, yaw -1..1, roll -1..1, and buttons boost, brake, flip, fire_primary, fire_secondary, dock, release. Every input device (06) maps to exactly this struct; the sim never knows what device produced it.

#### 3.1.3 Weapons and the two kill speeds

- **Guns** (autocannon, on Darts, Lancers and Autocannon Turrets): hitscan-free, simulated slugs at 700 m/s, 800 m range, **random damage per hit** (Dart gun: uniform 6-14 against a 100 HP Dart). Hits produce visible smoke/spark trails scaled by damage, so a target's state is readable without a health bar (Triplane's smoke, R1 s1.2). **Slugs, flak shells and rail slugs fly straight lines in the world frame (no parallel transport, no gravity); bombs and siege shells are CF-transported and fall under g; rockets are guided.** Lead solvers for humans, autopilots and towers are straight-line intercepts (R0 C1-03, Part B.5).
- **Bombs** (gravity bombs ejected downward at 40 m/s, falling under g with the ship's velocity carried, CF-transported like everything else): destroy any ship instantly; deal 400 damage to structures (a Pad has 600 HP, a Core 3,000). The main anti-ground weapon and a crude air-to-air weapon. A bomb sight marks the predicted impact point on the HUD.
- **Rockets** (Lancer, Missile Tower): guided, 250 m/s, 1,500 m, 40 damage, limited lock cone; countered by terrain masking and the flip.
- **Flak** (Flak Battery): 300 m/s shells, 1,500 m range, 25 m burst, 30 damage; cannot engage below 150 m altitude relative to the battery (minimum elevation), so flying low beats flak; Autocannon Turrets cannot engage above 400 m relative altitude (envelope `h_rel` -200 to +400 m, so a turret on a rim still covers the floor below it; 02 AR-2 accepted), so flying high beats them (Triplane's altitude counters, R1 s1.2).
- **Ramming**: a collision between two ships destroys both. A collision between a ship and a structure deals the ship's remaining HP as damage.
- No shields on ships in v1. Structures may have the Shield Projector dome (Section 6.2).

#### 3.1.4 Consumables and the resupply landing

Every ship carries **fuel** (Dart: 240 s of full thrust), **ammo** (Dart: 400 rounds, about 40 s of continuous fire) and **bombs** (Dart: 2). Hull damage persists until repaired. All three plus repair are restored only by landing on a friendly **Pad** (the Core has one; the Pad and Hangar structures add more). **Exception (08 A-1, accepted): a collected Supply Canister restores 40 % fuel and 50 % ammo in flight. Bombs and repair come only from landing.**

**Landing is a tail-down powered landing, Lunar-Lander style (owner decision 2026-10-10).** The ship pitches nose-up, hovers on its main engine and settles tail-first onto the pad; every ship carries landing legs on its tail and every ship can hover (`a_thrust >= 2 g` at low speed; Section 6.3). Landing rule: touch the pad with vertical speed <= 8 m/s, horizontal speed <= 15 m/s and the **body forward (thrust) axis within 25 degrees of the pad normal**: safe. Up to 15/25 m/s or 45 degrees: hull damage proportional to the excess. Beyond: destroyed. Once stopped on the pad the ship enters **DOCKED**: refuel 10 s, rearm 6 s, repair 15 s (run in parallel; a full service is 15 s), during which the ship is vulnerable unless the pad is a Hangar (bomb-proof, Section 6.2). Refuelling consumes 2 Ice per second from the team stockpile; rearming guns is free; each bomb costs 10 Ice; repair costs 1 Ore per 10 HP. The economy therefore bleeds through every sortie, and a team without ice cannot fly. Launch is tail-first along the pad normal; the pilot or autopilot pitches over above 20 m.

Every landing is **graded** (R0 C3-13): a quality score from touchdown speeds, tilt and centring gives ACE / CLEAN / FAIR / HARD (safe), BENT (damage band), CRASH, or AUTO (assisted). Grades award Pilot score directly (no banking) and drive the manual-landing repair bonus below; 02 owns the numbers, 08 SL-1 the formula.

Assist: **auto-dock** (default on for touch and gamepad, off for pointer) takes over the last 150 m of an approach when the `dock` button is held near a friendly pad; manual landings graded FAIR or better grant a 10 percent repair-time bonus and a score bonus (R1 s3 item 9).

#### 3.1.5 The ceiling

Altitude is measured from the datum sphere (|p| - R). Between 1,500 m (soft ceiling) and 2,000 m (hard ceiling), thrust efficiency fades linearly to zero and the HUD shows an "uplink fading" warning. At 2,000 m the possession link breaks: the entity is force-released to AUTO and its autopilot descends to 1,400 m before resuming its standing order. The player is told why in one line. This is Triplane's fainting pilot (R1 s1.2) expressed through the game's own possession rule and needs no atmosphere.

#### 3.1.6 Assist tiers (per input class, not per player)

Three assist tiers, chosen by input class defaults and overridable in options except in ranked where the class default is locked (R3 s5): **Full** (touch default: auto-level when the stick is neutral, auto-dock, aim assist cone 6 degrees, auto-throttle option), **Standard** (gamepad default: auto-level, auto-dock, aim assist 3 degrees), **Raw** (pointer default: none). Assists never change ship stats.

#### 3.1.7 Death and re-embodiment

When a possessed unit dies the camera holds on the wreck for 1.5 s, then the player is offered: nearest friendly unit of the same class, the Core (commander view), or any unit from the roster. There is no respawn timer because there is no avatar (R1 s3 item 2). Wrecks persist 90 s as salvage (Section 3.2).

### 3.2 Minute to minute: gather, refine, manufacture, build, defend

**Resources:** two stockpiles and one rate (Section 6.1): **Ore** (construction and manufacturing), **Ice** (fuel, bombs, some advanced builds) and **Power** (a rate; low power slows production and disables towers, C&C style, R1 s2.4). Stockpiles are per **team** (shared economy; Open question Q3).

**Gathering:** Harvesters (ground crawlers) mine Ore Fields and return to a Refinery, 300 Ore per trip at 12 m/s *(anchor)*. Ice comes from Cold Traps (discrete nodes in shadowed craters on the night hemisphere): an Ice Extractor built on a node fills a local buffer; if the node is inside a Refinery's supply radius the ice is piped automatically, otherwise Haulers (ships) ferry it. Two logistics styles: slow ground convoys that bombers love, and fast flying haulers that interceptors love.

**Refining and power:** Refineries convert deliveries into stockpile instantly and raise the storage cap (Core 3,000 Ore / 800 Ice, each Refinery +1,500 / +500, each Outpost +250 / +100; **there is no Storage Silo**, owner decision 2026-10-10). Solar Arrays produce only on the day hemisphere; Reactors produce anywhere at higher cost and explode when destroyed. Power below demand scales production speed and tower fire rate by the ratio; below 50 percent towers go offline.

**Manufacturing:** the Shipyard builds ships and the Vehicle Bay builds ground units, one queue each (5 items), from a production sidebar that is available in every camera tier (C&C's "production from anywhere", R1 s2.4). An **auto-replenish** toggle rebuilds lost units up to a target roster, essential for a player who is busy flying. **Every player starts with a Core, a Refinery, a Shipyard, a Vehicle Bay and one Harvester already mining** (800 Ore / 300 Ice per player; R0 C3-01), so the first decision is what to build, not whether production exists. A queued or placed item can be cancelled only by the player who queued it (or by anyone if that player is gone), and until 2:00 each player may spend at most their own 800 Ore share of the team pool (R0 C3-08).

**Building:** C&C-style placement. Structures are placed within the build radius of a Core (600 m), Outpost (400 m) or Relay Pylon (250 m), cost is paid up front, and the structure self-assembles over its build time *(anchor: 20-90 s)*. **Exception (02 AR-1, accepted): an Outpost needs no radius; it needs a friendly unit within 300 m of the site at placement, >= 800 m from every friendly Core/Outpost and >= 1,500 m from every enemy Core/Outpost**, which is what lets expansion reach contested fields and the poles. No builder units in v1 (removes a ground-pathing class). Pylons also form the **supply network**: towers inside a pylon's radius draw ammo and power automatically (R1 s3 item 12), with visible pools that drain under siege.

**Defending:** four towers with distinct counter-altitudes and roles (Section 6.2). Towers are AUTO by default and possessable for manual aim.

**Salvage:** a destroyed ship or structure leaves a wreck worth 40 percent of its Ore cost for 90 s. Haulers tow wrecks with a tractor tether (a Thrust homage: the load swings on the tether, R1 s2.5) to a Refinery. Wrecks are the comeback mechanism: losing a fight on your own ground leaves resources at your doorstep (R1 s3 item 13).

### 3.3 Match arc

| Phase | Clock | What happens | Design intent |
|---|---|---|---|
| Open | 0-5 min | Solar, second Harvester, first Dart (the Shipyard is pre-built); scout the neighbour; claim the near Cold Trap. | Decisions in the first 60 s; a Dart in the air by 0:45 (median ~0:30) so pilots are flying early. The Core's integrated shield (2,400 charge, no Ice, until 8:00) blocks a bomb rush (R0 C3-05). |
| Expand | 5-15 min | Outposts toward contested Ore Fields; towers on approach vectors; first bomber raids on harvester lines; poles contested by 10:00. | Map control, convoy raiding, "where is the fight" readability. |
| Siege | 15-30 min | Heavy ships, Shield Projectors, Rail Lances; Core assaults with escorts; wreck salvage swings. | Decisive, visible, rematch-friendly. |
| Overtime | 30-40 min | **Core Exposure** at 30:00: Shield Projectors over Cores lose 50 percent effectiveness, Cores take 125 percent bomb damage and Ore Fields stop regenerating. | Prevents turtling stalemates (Sacrifice's failure, R1 s2.2). |
| Hard end | 40:00 | Team with the highest surviving structure value wins. | Hard cap for mobile sessions and matchmaking. |

The clock values above are the long-form (team and custom) defaults. **Core Exposure and the hard end are per-mode data** (R0 C3-19): `pvp_1v1` 20:00 / 30:00, `pvp_2v2` 25:00 / 35:00, `pvp_team`, `coop`, `custom`, `skirmish` 30:00 / 40:00, campaign per mission; the arc phases scale with them.

**Target typical length 20-30 minutes** (median 24 in bot-vs-bot soak tests, Section 7 ADR-11). **Victory:** destroy every enemy Core. A player whose Core dies is **eliminated as a commander** (cannot build) but **stays in the match as a pilot** of team units until the last team Core falls (pillar P1; Triplane's "no game over by death"). Their structures stay for 60 s then self-destruct.

### 3.4 Meta and progression (fair PvP)

- Everything that affects gameplay is available to every player from the first match: all ships, structures, towers and all three **Doctrines** (Section 6.4).
- Progression is cosmetic and social only: account level, ranks, hull paints, pad flags, callsign titles, campaign medals. The campaign unlocks paints, never stats.
- Skill rating per queue (`pvp_1v1`, `pvp_2v2`, `pvp_team` = 3v3/4v4 pooled; all three queues exist at launch with bot fill), seasonal reset, visible rank. Ratings are recorded from launch but are not used for matching until the first season patch (R0 C3-15; Q13). Ratings and unlocks are server-authoritative (R3 s7.13).
- Monetisation (Open question Q2): no randomised paid items, ever (R3 s6.5); no gameplay purchases.

---

## 4. Control model

### 4.1 Three camera tiers

| Tier | Altitude band (above datum) | Purpose | Input |
|---|---|---|---|
| **Chase** | follows the possessed unit (35 m behind a Dart) | fly / aim | PilotInput |
| **Tactical** | 300-2,500 m, orbiting a surface focus point | select, order, place buildings, watch a front | selection + orders |
| **Commander** | 2,500-14,000 m, globe rotation | whole-war overview, alerts, production sidebar, jump to anything | selection + orders |

Zoom between Tactical and Commander is continuous (pinch / wheel), Gravitar-style (R1 s2.5). Possess animates the camera from the current view to Chase in 0.5 s; release returns to Tactical over the unit. The camera's up vector is the local surface normal with damped roll (Mario Galaxy 2 lesson, R1 s2.6); controls are ship-relative so a lagging camera never changes what "left" means. 06 owns the full camera spec.

### 4.2 Control state per entity

Every entity has exactly one control state:

| State | Meaning | Who drives |
|---|---|---|
| **AUTO** | No standing order; class autopilot picks its own behaviour (Section 4.3). | sim_ai autopilot |
| **ORDERED** | A player-issued standing order (move, patrol, attack, escort, harvest-here, haul, return, hold, guard) is being executed. When it completes or becomes impossible, the entity returns to AUTO. | sim_ai autopilot executing the order |
| **POSSESSED(player)** | A human (or, in replays, a recorded human) supplies PilotInput each tick. | the player |

Structures use the same states: a Shipyard in AUTO runs its queue; a tower in AUTO picks targets; a POSSESSED tower aims where the player aims; a POSSESSED Shipyard opens its production UI and nothing else (possessing a structure is mostly a camera-and-UI convenience, plus manual aim for towers).

### 4.3 What "automatic" means per entity class (v1 roster)

| Class | AUTO behaviour | Return-to-pad rule |
|---|---|---|
| Dart (interceptor) | Patrol a 1,200 m radius around its home pad or last ordered point; intercept hostiles seen by team sensors within 2,000 m; prefer harvesters and bombers over fighters. | fuel < 25 %, ammo = 0, or HP < 40 % |
| Lancer (gunship) | Guard the nearest friendly structure cluster; engage ground targets first. | same |
| Bomber | Stay docked until ORDERED; when the order ends, return and dock. Never free-roams (too valuable). | always after a run |
| Scout | Fly an expanding search pattern from home; flee on contact. | fuel < 25 % |
| Hauler | Ferry: nearest Ice Extractor buffer -> nearest Refinery; if a wreck is within 800 m of the route and no enemy is within 1,000 m, tow it. | fuel < 25 % |
| Harvester (ground) | Mine nearest Ore Field with free capacity; return at 300 Ore; flee from attackers toward the nearest tower. | n/a (no fuel) |
| Siege Crawler (ground; **kept in v1**, owner decision 2026-10-10) | Hold position unless ORDERED. | n/a |
| Towers | Target priority: bombers > haulers with cargo > Lancers > Darts > Siege Crawlers > Harvesters > Scouts > empty Haulers (data in `towers.json`); respect altitude envelopes. | n/a |
| Shipyard / Vehicle Bay | Run the queue; auto-replenish if enabled. | n/a |
| Pad / Hangar | Service docked ships in arrival order. | n/a |
| Core, Solar, Reactor, Refinery, Pylon, Sensor Mast, Extractor | Passive. Sensor Mast raises alerts. | n/a |

An optional **Adjutant** (a throttled version of the Commander bot, 05) can run a human player's economy and replenishment when toggled on (`Command.SET_ADJUTANT`). Default on in Skirmish and Campaign, selectable in Co-op. **In PvP quick-match queues a restricted `adjutant_economy` profile (Harvester count, power balance, replenishment; no towers, no Outposts, no other production) may be enabled and is shown to opponents as the lobby tag "Auto economy"** (owner decision 2026-10-10; keeps pillar P1 true for pure pilots). It is off in the visible ranked ladder that arrives after launch (Q13).

### 4.4 Handoff rules

1. **Possess** (`Command.POSSESS(entity)`): valid if the entity is alive, belongs to the player's team, is possessable (all units and towers, Shipyards/Vehicle Bays for UI, not Cores/passive structures), and is not already possessed. The server stamps `POSSESSED(player)`, stores the current standing order as `saved_order`, and tells all teammates. The client starts prediction on the server's acknowledgement; until then it plays the camera transition, which hides one round trip.
2. **Release** (`Command.RELEASE`, or possessing something else, or death, or the hard ceiling, or disconnect): the autopilot first performs a **safety handoff** (take over the current velocity; if the ship is within 2 s of terrain impact, pull up; if below 20 percent fuel, set the order to return), then resumes `saved_order` if it is still valid, otherwise AUTO.
3. **Orders during possession:** teammates (and the player, from the sidebar) may issue orders to a possessed unit; they are stored as `pending_order`, shown to the pilot as a HUD suggestion, and become the standing order on release. They never seize control.
4. **One pilot per entity.** A second player sees "piloted by <name>" and may send a one-tap **request**; the pilot can **hand over** (swap in place, the requester's prediction starts next tick) or ignore. No forced takeover in v1.
5. **Team-shared command.** Every teammate can order any team unit and build with the team stockpile. Production queues are team-shared; the lobby shows who queued what.
6. **Disconnect:** possessed units are released with the safety handoff; the player's commander rights persist for 120 s for reconnection (ADR-07), after which the Adjutant takes over the player's slot as a bot until they return.
7. **Cooldowns:** none on possess/release in v1; the Doctrine system (02) may add a 1-3 s possess delay to specific heavy units if hopping proves abusive.

---

## 5. World

### 5.1 Why R = 6,000 m

Derivation, from gameplay first and precision second:

1. **Travel rhythm.** Triplane's sortie rhythm is "cross the screen in ~20 s, bomb, come home". Our Dart cruises at 110 m/s. For 8 bases on a great circle, neighbours are 45 degrees apart: 4,712 m, 43 s. The antipode is 171 s away, but no layout uses it: 1v1 bases sit 90 degrees apart, 86 s (Section 5.7). Those match C&C-class RTS crossing times (1-3 min) and give a 3-6 minute sortie including the fight and landing, which fits a 240 s fuel tank.
2. **Density.** 452 km^2 total, 56.5 km^2 per player at 8 players, a circle of radius 4.2 km: room for a base, two ore fields, a cold trap and contested ground between neighbours, without the emptiness reviewers disliked in Planetary Annihilation (R1 s2.1).
3. **Precision.** Maximum simulated magnitude is R + hard ceiling = 8,000 m, inside the official float32 band [4,096, 8,192) with 0.5 mm steps, the recommended third-person maximum (R2 s7.1). No floating origin, no double builds (ADR-03).
4. **Data size.** Six cube faces at 1,024^2 u16 give 9.2 m texels at R = 6,000 and 12.6 MB raw (about 4 MB compressed) per map, which fits the 20 MB web budget. At R2's suggested 20 km, the same texel size would need 139 MB.
5. **Still "very large".** From a 12 m Dart at 100 m altitude the horizon is 1.1 km away and the curvature is visible; the commander view at 14 km altitude sees 35 percent of the surface at once.

R2 s7.3 recommended 10-20 km from precision headroom alone; we choose the smaller radius because gameplay, data size and mobile performance all prefer it and precision is not a constraint at 6 km. **The owner confirmed R = 6,000 m on 2026-10-10; it is no longer an anchor.** `PLANET_RADIUS` is a single constant in `core/sphere.gd`; spike S-WORLD-1 still renders 4, 6 and 8 km variants to prove the renderer is radius-agnostic, not to move R. For small player counts the fix for travel time is slot spacing (Section 5.7), not radius. Ship speeds are tuned to R, not the reverse.

### 5.2 Scale table (canonical numbers)

| Quantity | Value | Derivation / note |
|---|---|---|
| Unit | 1 unit = 1 m | |
| Datum radius R | 6,000 m | Section 5.1; **fixed (owner, 2026-10-10)** |
| Circumference | 37,699 m | 2 pi R |
| Surface area | 452 km^2 | 4 pi R^2 |
| Area per player at 8 players | 56.5 km^2 | |
| Terrain relief | -500 m (mare floors, crater floors) to +700 m (rims, ridges) relative to datum | 07 bakes within this range |
| Gravity g | 6.0 m/s^2, constant, toward the core | Section 3.1.1 *(anchor 5-8)* |
| Soft ceiling / hard ceiling | 1,500 m / 2,000 m above datum | Section 3.1.5 |
| Max simulated magnitude | 8,000 m | < 8,192 (0.5 mm float32 step) |
| Commander camera altitude | 2,500-14,000 m | camera magnitude <= 20,000 (1.9 mm step; nothing small is rendered there) |
| Horizon distance from 50 / 100 / 300 / 1,500 m altitude | 776 / 1,100 / 1,921 / 4,500 m | sqrt(2Rh + h^2) |
| Dart cruise / boost (6 s, 20 s cooldown) / dive cap | 110 / 160 / 190 m/s | *(anchor +-15 %)* |
| Lancer / Bomber / Hauler (loaded) / Scout | 80 / 70 / 45 (35) / 140 m/s | *(anchor)* |
| Harvester / Siege Crawler | 12 / 8 m/s | ground |
| Dart turn rates: pitch / yaw / roll | 120 / 60 / 180 deg/s | *(anchor)* |
| Antipode at Dart cruise | 171 s | pi R / 110; no v1 layout places enemies at the antipode |
| Start slot k longitude | 22.5 + 45 k degrees | k = 0..7; no slot within 10 degrees of a cube edge (R0 C1-09) |
| Adjacent bases, 8 players (45 deg) | 4,712 m, 43 s | |
| Adjacent bases, 4 players and 1v1 (90 deg) | 9,425 m, 86 s | 1v1 uses slots 0 and 2 (owner, 2026-10-10) |
| Either pole from any base | 9,425 m, 86 s | neutral objectives |
| Gun / rocket / flak range | 800 / 1,500 / 1,500 m | |
| Sensor range: Dart / tower / Core / Sensor Mast | 1,400 / 1,600 / 2,000 / 3,500 m | plus horizon occlusion |
| Build radius: Core / Outpost / Pylon | 600 / 400 / 250 m | |
| Sim tick | 30 Hz (33.33 ms) | ADR-06 |
| Heightfield | 6 x 1024^2 x u16 = 12.6 MB raw per map | ~9.2 m texels at face centre |
| Occupancy / build grid | 6 x 1024^2 cells, 1 cell = 1 texel | ADR-05 |
| Ground pathing grid | 6 x 256^2 cells (~37 m) | ADR-05 |
| Interest cells | 6 x 8 x 8 = 384 cells (~1,178 m) | ADR-05/07 |
| Collision hash | 6 x 64 x 64 = 24,576 cells (~147 m) | ADR-05 |
| Sun | fixed direction +Z; terminator = equator | Section 5.5 |
| Optional sun rotation (custom/campaign rule) | 60 min period, off in matchmade | Section 5.5 |

### 5.3 Altitude layers

| Band (above datum) | Name | Rules |
|---|---|---|
| terrain to +150 m above local ground | Deck | below Flak minimum elevation; inside Autocannon envelope; hidden behind the horizon from most sensors; terrain impact risk |
| 150-400 m | Low | both tower types reach you |
| 400-1,500 m | High | above Autocannon envelope; Flak and Missile Towers only; visible from far away |
| 1,500-2,000 m | Fade | thrust fades to zero; HUD warning |
| >= 2,000 m | Ceiling | forced release, autopilot descent |

### 5.4 Terrain features

| Feature | Scale | Gameplay role |
|---|---|---|
| **Maria** (dark basins) | 3-8 km across, flat, -200 to -500 m | prime base ground; Ore Fields; open approach, no cover |
| **Impact craters** | 50 m - 3 km diameter; rims +50 to +400 m, floors -100 to -300 m | rims block line of sight for deck flyers; floors are natural fortresses; small craters are visual texture only |
| **Highlands** | rugged, +200 to +700 m | slow for Harvesters (slope), great for Sensor Masts and Flak |
| **Rilles** (sinuous canyons) | 30-100 m deep, 100-300 m wide, 2-10 km long | hidden low-flight corridors between regions |
| **Cold Traps** | 200-800 m craters on the night hemisphere whose floors are permanently shadowed | the only Ice sources; richer toward the Midnight Pole |
| **Solar Plateau** | ~2 km flat plateau at the Noon Pole | +50 % Solar yield; neutral; the day-side objective |
| **Boulder fields, ejecta rays** | props | visual only, no collision for ships above 10 m |

Terrain never deforms (ADR-04); bomb craters are decals.

### 5.5 Sun, day and night: decision

**Decision: the sun does not move in matchmade PvP. It is fixed along +Z (the moon's polar axis), so the terminator is the equator and does not drift.** All start positions lie on the equator, equally spaced, so every player has identical access to day (solar power, north) and night (ice, south). The Noon Pole and the Midnight Pole are equidistant from all bases and become the two neutral objectives. A static terminator is fair for any N, trivially readable and cheap.

A **moving sun (period 60 min, moon rotating about an axis in the equatorial plane)** exists as a per-map rule for Campaign, Co-op and custom lobbies, default off. It is a good campaign device (a base that will fall into night in ten minutes) but it breaks symmetric starts, so it never enters ranked play. 02 may tune the period; 08 may propose mechanics that use it.

**Night is readable.** The night hemisphere is lit by "earthshine": a dim blue-grey ambient plus emissive team colours and lit pads, so a phone screen outdoors still reads it. 07 owns the lighting spec; 06 owns the readability tests.

### 5.6 Resource distribution (template for 02 and 07)

For each of the 8 equatorial start slots (slot k at longitude 22.5 + 45 k degrees, Section 5.7; matches with fewer players use the slot subsets of Section 5.7, never 360/N spacing):

- **Home Ore Fields:** two fields of 6,000 Ore each within 1,000-1,500 m of the Core, one on each side.
- **Home Cold Trap:** one small trap (2,000 Ice, 0.8 Ice/s extraction) 1,500-2,000 m south.
- **Contested Ore Field:** one field of 10,000 Ore at the midpoint between neighbouring bases, slightly north (day side, so towers there get solar).
- **Mid-latitude Cold Traps:** medium traps (6,000 Ice, 1.5 Ice/s) at about 45 degrees south between each pair of bases.
- **Midnight Pole:** the richest trap cluster (20,000 Ice, 3 Ice/s) plus pre-placed neutral terrain cover.
- **Noon Pole:** the Solar Plateau and a neutral, capturable **Relay Station** (Section 6.2) that grants a pad and sensor coverage.

Unused start positions (fewer than 8 players) keep their fields at 50 percent yield so the map stays symmetric without becoming an economy buffet. *(all anchors; 02 balances)*

### 5.7 Start positions and team layout

- Every map has 8 equatorial slots; **slot k sits at longitude 22.5 + 45 k degrees** (k = 0..7), so no base lies within 10 degrees of a cube-face edge (R0 C1-09; face 0 holds slot 0 at (u, v) = (0.75, 0.5)).
- **Slot subsets by player count (owner decision 2026-10-10):** 2 players use slots 0 and 2 (90 degrees apart, 9,425 m, 86 s: a 1v1 raid sortie fits the 4-minute sortie model); 4 players use 0/2/4/6; 6 players use 0/1/2 and 4/5/6; 8 players use all. Odd human counts in custom lobbies are filled with bots to the next even count. The 24-slot / 15 degree scheme of v1.0 is withdrawn. Unused slots keep their resource features at 50 percent yield (Section 5.6).
- Teams occupy **contiguous blocks** in matchmade play (4v4: team A at slots 0-3, team B at 4-7; 3v3: 0-2 vs 4-6; 2v2: 0, 2 vs 4, 6), giving each team a frontier and a protected interior. Custom lobbies may choose alternating slots.
- Each Core faces "north" (toward the day side) on spawn; the first camera orientation is identical for everyone.

---

## 6. High-level content roster (one line each; 02 expands and balances)

### 6.1 Resources

| Resource | Kind | Source | Spent on |
|---|---|---|---|
| **Ore** | stockpile (team) | Ore Fields via Harvesters; wreck salvage via Haulers | structures, ships, ground units, repair |
| **Ice** | stockpile (team) | Cold Traps via Ice Extractors (+ Haulers) | fuel, bombs, Reactors (build cost), Shield Projector charge |
| **Power** | rate (team) | Solar Arrays (day only), Reactors | production speed, tower uptime, shield uptime |

### 6.2 Structures

| Structure | Role | Notes |
|---|---|---|
| **Command Core** | HQ; 600 m build radius; one pad (12 m); 2,000 m sensors; 3,000 HP; stores 3,000 Ore / 800 Ice; **integrated shield** (2,400 charge, recharge 40/s after 5 s, no Ice cost) that absorbs bombs and rockets until 8:00 (R0 C3-05). | Loss eliminates the player as commander. Cannot be rebuilt. Pre-built with a Refinery, Shipyard and Vehicle Bay (Section 3.2). |
| **Outpost** | Forward mini-core: 400 m build radius, one pad (10 m), 1,200 m sensors, +250 / +100 storage. Placed by presence (a friendly unit within 300 m; spacing 800 m friendly / 1,500 m enemy), not by radius (02 AR-1). | Enables expansion to contested fields and the poles. |
| **Relay Pylon** | Extends build radius 250 m and carries the supply network (ammo/power) to towers. | Cheap, chainable, fragile: the "cut the supply line" target. |
| **Solar Array** | Power on the day hemisphere; +50 % on the Solar Plateau; zero at night. | Cheap. |
| **Reactor** | Constant power anywhere; costs Ice to build; explodes (100 m, 200 damage) when destroyed. | Expensive, dangerous to place near the Core. |
| **Refinery** | Delivery point for Ore and Ice; 500 m automatic pipe radius for Extractors; +1,500 Ore / +500 Ice storage. | Harvesters and Haulers queue to unload. The Storage Silo of v1.0 is cut (owner, 2026-10-10); Refineries and the Core carry the caps. |
| **Ice Extractor** | Built on a Cold Trap node; fills a local buffer. | The only structure allowed on a resource node. |
| **Pad** | Landing pad (10 m): refuel, rearm, repair one ship at a time. | Open to the sky; bombable. |
| **Hangar** | Pad plus bomb-proof roof; services one ship; +50 % cost. | Triplane's bomb-proof hangar, as an upgrade choice. |
| **Shipyard** | Manufactures ships; one queue; launches onto its own pad. | Rate scales with power. One is pre-built per player. |
| **Vehicle Bay** | Manufactures Harvesters and Siege Crawlers. | One is pre-built per player. |
| **Sensor Mast** | 3,500 m sensors, reveals deck flyers within 1,200 m regardless of horizon; raises alerts. | Tall silhouette; a priority bombing target. |
| **Autocannon Turret** | Tower. Short range (700 m), envelope 0-400 m altitude, 5-round bursts, random damage. | Beaten by flying high. |
| **Flak Battery** | Tower. 1,500 m range, minimum elevation 150 m, slow area shells. | Beaten by flying low. |
| **Missile Tower** | Tower. 1,500 m lock-on rockets, strong vs bombers and haulers, 6 s reload. | Beaten by terrain masking and the flip. |
| **Shield Projector** | Tower-class support: 250 m dome that absorbs bombs and rockets (not guns) while charged; drains Power and Ice. | Protects a Core cluster; halved at Core Exposure. |
| **Rail Lance** (late game; **kept in v1**, owner 2026-10-10) | Tower. 2,500 m single-target heavy shot every 8 s (1,500 m/s straight slug, 1.7 s flight); anti-capital. | Beaten by jinking during the slug flight. |
| **Relay Station** (neutral, pre-placed at the Noon Pole) | Capturable by landing a Hauler on it (12 m pad) for 20 s with no enemy within 300 m; grants a pad and 3,500 m sensors to the holder. | The day-side objective. |

### 6.3 Units

| Unit | Type | Role | Loadout anchors |
|---|---|---|---|
| **Dart** | ship | Interceptor; the Triplane plane; the default possession. | gun, 2 bombs, 100 HP, 240 s fuel, `a_thrust` 24 (4 g) |
| **Lancer** | ship | Gunship; anti-ground; escorts bombers. | gun, 8 rockets, 220 HP, 300 s fuel, `a_thrust` 18 (3 g) |
| **Bomber** | ship | Heavy bomber; the siege weapon; must be escorted. | 6 bombs, 300 HP, 360 s fuel, no gun, `a_thrust` 14 (2.3 g) |
| **Scout** | ship | Cheap, fast, unarmed, 2,000 m sensors; reveals and dies. | 40 HP, 180 s fuel, `a_thrust` 30 (5 g) |
| **Hauler** | ship | Ice ferry, wreck tug (rigid tether, 25 m), Relay Station capture. | 120 HP, 400 s fuel, 400 Ice cargo, `a_thrust` 15 (2.5 g) |
| **Harvester** | ground | Ore mining crawler. | 150 HP, 300 Ore cargo, 12 m/s |
| **Siege Crawler** | ground (**v1**, owner 2026-10-10) | Slow anti-structure artillery (1,200 m, lofted shells); needs escort; a fun possession. | 400 HP, 8 m/s |
| **Barge** (v1.x idea; 08 I-01: anchored variant v1.x, moving deck v2) | ship | Mobile pad: a slow capital that ships can land on. | 08 evaluates |

Every ship hovers: `a_thrust >= 2.0 g` (12 m/s^2) is a schema minimum so the tail-down landing (Section 3.1.4) has margin on every class. The tow tether is a kinematic rigid link (wreck 25 m behind, 8 m below, critically damped); swing is presentation only (R0 C3-17). Canonical values for every field are in R0 Part B.1.

### 6.4 Doctrines (asymmetry via data, Triplane's four nations re-imagined)

Chosen per player in the lobby; all available to everyone; implemented purely as stat multipliers and one rule tweak each in JSON (R1 s1.2 trade-offs, s3 item 14):

| Doctrine | Strength | Weakness |
|---|---|---|
| **Vanguard** | +15 % ship speed and turn rate; flip cooldown 1 s | -20 % hull; Dart carries 1 bomb |
| **Bulwark** | +25 % structure HP; towers +10 % range; Hangar roof also blocks rockets | -10 % ship speed; +15 % structure cost |
| **Foundry** | -15 % structure and unit cost; Harvesters +25 % cargo; Haulers tow 2 wrecks | -15 % ship damage; Reactor forbidden until 10:00 |

---

## 7. Technical architecture decision records

Each ADR: Decision / Alternatives / Rationale / Consequences. Facts cite R2 unless noted.

### ADR-01 Engine version policy and scripting language

**Decision.** Godot **4.7.2-stable** (released 2026-08-18), pinned in `.godot-version`, the CI Docker tag (`barichello/godot-ci:4.7.2-stable`) and `project.godot`. 4.7.x patch releases are adopted within a week of release; the move to 4.8 is a scheduled task that starts no earlier than **4.8.1** (R2 s1.2). All gameplay, server and tooling-inside-Godot code is **typed GDScript** with the R2 s4.3 warning set at level Error (`untyped_declaration`, `inferred_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument`, `unsafe_cast`, `unsafe_void_return`, `return_value_discarded`, `missing_await`, `unused_variable`, `unused_parameter`, `shadowed_variable`, `integer_division`, `narrowing_conversion`). **No C#.** **No GDExtension in v1.** From v1.1, a native GDExtension (godot-cpp 10.x) may be added only as a *twin* of an existing GDScript module behind the same interface, selected at runtime by feature tag; the web export always runs the GDScript twin (`web_noextensions`). Addon allowlist: gdUnit4 6.2.x, nakama-godot, and from v1.1 webrtc-native 1.2.x and GodotSteam (desktop only). Jolt is set as the physics engine in `project.godot` but is not used anywhere in v1, not even for debris (ADR-06 as amended; 03 amendment 2 accepted).

**Alternatives.** C# (installed .NET SDK; faster numeric code): rejected because C# cannot export to the web in 4.7.2 or 4.8-dev7, Android/iOS C# is experimental, and 4.8 raises the floor to .NET 10 (R2 s4.1). GDExtension-first: rejected for v1 because web GDExtension forfeits the single-threaded, header-free hosting story the portals require (R2 s3.1, R3 s4). 4.8 at launch: rejected; it has no beta as of 2026-09-29.

**Rationale.** One code path on every platform including the browser (pillar P4/O10). Typed GDScript with warnings-as-errors makes "an agent wrote untyped code" a failing headless run, the cheapest possible gate for a multi-agent team.

**Consequences.** GDScript is 10-100x slower than C++ in tight loops (R2 s4.2), so the sim is written data-oriented from day one (ADR-06) and spike S-SIM-1 validates 1,200 entities at 30 Hz. Hot paths must be written behind interfaces so a native twin can replace them later without touching callers. No agent may add an addon outside the allowlist without an ADR amendment.

### ADR-02 Renderer per platform

**Decision.** **Compatibility (OpenGL 3.3 / GLES 3.0 / WebGL 2) on every platform in v1**: Windows, macOS, Linux, Android, iOS, web, and the headless server (which renders nothing). Art, shaders and effects are authored and signed off on Compatibility. A `Mobile` renderer profile for high-end native devices may be *evaluated* in v1.x as an opt-in quality setting; it may never be required for anything gameplay-relevant. Forward+ is never a target.

**Alternatives.** Forward+/Mobile on native with Compatibility only on web: rejected because it doubles art QA, risks platform-dependent readability (pillar P4), and the iOS simulator supports only Compatibility anyway (R3 s1). WebGPU: not supported upstream (R2 s2.3).

**Rationale.** The web build has exactly one option (R2 s2.1), low-end Android needs it, and flat-shaded low-poly art does not benefit from the RD renderers' features.

**Consequences.** No compute shaders: terrain meshing and any flow-field work run on the CPU with per-frame budgets, or in vertex shaders for visuals (ADR-04). 24-bit non-reverse-Z depth: the camera near plane scales with altitude (0.3 m at ground level in Chase, 4 m in Tactical, 20 m in Commander; far plane 40,000 m so the limb is always visible), verified by spike S-WORLD-1. No decals in 4.7: bomb scorch marks are camera-facing quads until 4.8. No shader baker on Compatibility: the loading screen pre-warms one instance of every material and particle effect. Light budget: one directional sun, earthshine ambient, at most 8 local lights per mesh (pads, explosions), shadows from the sun only, off on low mobile tier.

### ADR-03 Coordinate systems and float precision

**Decision.** One world frame for simulation *and* rendering: moon-centred, **float32 `Vector3`**, +Z toward the sun (Noon Pole), +X toward longitude 0 (the centre of cube face 0; **start slot 0 sits at longitude 22.5 degrees**, Section 5.7). **No floating origin, no camera-relative rendering, no `precision=double` build.** Maximum simulated magnitude 8,000 m (0.5 mm step); camera magnitude up to 20,000 m (1.9 mm step). Derived frames, all computed by `core/sphere.gd`:

| Frame | Definition | Used for |
|---|---|---|
| World | moon-centred Cartesian | sim state, rendering, networking (quantised per cell) |
| Tangent (ENU) | up = normalize(p); north = normalize(+Z - (+Z.up)up); east = north x up | flight model, camera up, HUD horizon, orders ("move 500 m north") |
| Body | ship basis B (forward, up, right) | PilotInput, thrust, weapons |
| Cube-face | (face 0-5, u, v in [0,1]) equal-angle cube-sphere mapping | terrain texels, build grid, path grid, interest cells, hash cells |
| Geodetic | latitude, longitude | UI, map labels, start slots (slot k at longitude 22.5 + 45 k degrees) |

Server and client builds share the same precision; cross-platform **determinism is explicitly not required** because the server is authoritative and clients only predict their one possessed unit (ADR-07).

**Alternatives.** float64 sim state in `PackedFloat64Array` (R2 s7.3): rejected because at 8 km the float32 error (0.5 mm per operation against a 3.7 m per-tick displacement) is irrelevant and scalar GDScript math is several times slower than `Vector3` built-ins. Floating origin: rejected; the docs call it complex in multiplayer and the magnitude does not need it. Double builds: no official templates, no mobile/web CI (R2 s7.2).

**Rationale.** The smallest architecture that satisfies the official precision table.

**Consequences.** `PLANET_RADIUS` is fixed at 6,000 m (owner); R + hard ceiling = 8,000 < 8,192. Any proposal to move it triggers an ADR amendment and, above 6,100, the camera-relative rendering design from R2 s7.3.

### ADR-04 Terrain representation, LOD, collision, deformation

**Decision.** **Cube-sphere quadtree chunked LOD**, implemented in GDScript (reference: `cuberact/godot-cuberact-planet-chunked-lod`, MIT, R2 s8; study it, do not vendor it wholesale). Per map, an offline Python baker (`tools/moonbake/`) produces: six u16 height faces at 1,024^2 (relief mapped to -500..+700 m), six u8 biome/material faces at 1,024^2, a feature list (craters, fields, cold traps, slots) and a normal-map-free "colour ramp" spec. Chunks are 33 x 33 vertices (2,048 grid triangles plus 256 skirt triangles; 03 amendment 3), depth 0-6 (depth 6 chunk = 1/64 face = about 147 m across, 4.6 m vertex spacing), selected by camera distance; a per-frame mesh-build budget of 2 chunks on mobile and 6 on PC (with the rule that one build always runs when the queue has waited 2 frames), with chunk pooling and horizon culling (a chunk whose bounding sphere is entirely beyond the horizon from the camera is skipped). The mesher reads heights by texel index, never through `height_at`; S-WORLD-1 also evaluates a GPU vertex-displacement variant and picks per tier (R0 C1-06). Visual detail (small craters, regolith grain) comes from a vertex-shader displacement and a triplanar-free material driven by the biome face; it has **no gameplay meaning**. **Gameplay height is the bilinear sample of the baked u16 face** (`Terrain.height_at(dir: Vector3) -> float`), identical on server and client. **No deformation**; impacts leave decal quads (presentation only).

**Alternatives.** Icosphere mesh: better uniformity, worse texture mapping and quadtree logic. Voxel terrain (Zylann): needs a custom engine build (R2 s8). Runtime procedural generation from a seed: rejected for gameplay data because FastNoiseLite's cross-platform bit-exactness is unverified (R2 s8) and because bake-time authoring is what lets Haiku agents write map recipes. Deformable terrain: rejected; it breaks the baked-height contract and adds netcode.

**Rationale.** Cube-sphere gives one addressing scheme for terrain, grids and cells (ADR-05); baking gives determinism and tiny map files; GDScript keeps the web build.

**Consequences.** The web build streams a map's 4 MB (compressed) as a separate `.pck` after the core pack. Map authoring is a recipe JSON plus a bake step in CI. Chunk builds on single-threaded web run inline with the budget above; spike S-WORLD-1 measures. A GDExtension twin of the mesher is the first native-twin candidate.

### ADR-05 Gameplay grid and spatial index on the sphere

**Decision.** All spatial bookkeeping uses the cube-face addressing of ADR-03 at four resolutions:

| Layer | Resolution | Cell size | Storage | Purpose |
|---|---|---|---|---|
| Occupancy / build grid | 6 x 1024^2 | ~9 m (1 texel) | 6 `PackedByteArray` (6 MB) | structure footprints, placement validity, resource node marks |
| Ground path grid | 6 x 256^2 | ~37 m | weights in `PackedByteArray`; our own A* with hierarchical face-level abstraction | Harvester and Siege Crawler routes; re-weight only touched cells when structures change |
| Interest cells | 6 x 8 x 8 = 384 | ~1,178 m | entity id lists per cell | network interest management, team vision aggregation, alert regions |
| Collision hash | 6 x 64 x 64 = 24,576 | ~147 m | `Dictionary[int, PackedInt32Array]` rebuilt per tick | swept projectile vs entity, neighbour queries for autopilots |

**Placement rules:** a structure may be placed when every footprint cell is free, the maximum slope across the footprint is <= 15 degrees, the footprint is inside team vision and outside every enemy build radius, the footprint centre is within a friendly build radius (**except the Outpost, which uses the presence and spacing rule of Section 3.2**), and the footprint does not overlap a resource node unless the structure is an Ice Extractor on a Cold Trap. `Build.can_place(player, def_id, cell, rotation) -> Build.Reject` is the one validator, used by server, client preview and protocol layer alike (R0 B.3). Structures snap to the grid; ships do not.

**Ground navigation** is time-sliced: A* expands at most `rules.path_expansions_per_tick` (anchor 2,000) nodes per tick across all queued requests, answers by ticket, and caches routes by (start cluster, goal cell) (R0 C1-05).

**Fog of war / vision:** team vision is the union of all team entities' sensor discs, with **horizon occlusion against the datum sphere** (a segment that intersects the R-sphere is occluded) and the Sensor Mast's deck-reveal exception. Terrain line-of-sight (crater rims hiding ships) is **not** simulated in v1 (v1.x candidate, needs a height-field march per check). Enemy entities outside team vision are not sent to clients (ADR-07); the Commander view shows last-known ghosts for 30 s.

**Ground navigation** uses our own A* on the path grid, never `NavigationServer3D`, whose single map up-vector breaks funnelling on the far hemisphere (R2 s9.1). `AStar3D` may be used as the search container if its performance is adequate (spike S-NAV-1).

**Alternatives.** Icosphere geodesic grid (R2 s9.2): uniform cells, but a second addressing scheme beside the cube-sphere terrain. Godot NavigationServer with hand-built meshes: unproven on spheres.

**Rationale.** One addressing scheme, cheap integer cell ids, data in packed arrays, deterministic rebuilds.

**Consequences.** Cell sizes vary about 30 percent between face centre and corners; all radius queries use true great-circle distance after the cell pre-filter. 03 specifies the exact face mapping and neighbour-across-edge tables.

### ADR-06 Simulation architecture

**Decision.** A **server-authoritative, fixed-tick (30 Hz) simulation** in `src/sim/`, implemented as `RefCounted` classes with **no `Node` dependency**, so it runs identically in the dedicated server, in the in-process local server for offline modes, and in headless tests. Entity state is **structure-of-arrays** in packed arrays (`PackedVector3Array` for position/velocity, `PackedFloat32Array` for scalars, `PackedInt32Array` for ids/types/owners/states, `PackedByteArray` for flags) indexed by slot, with `EntityId = slot | (generation << 20)` (max 1,048,576 slots, generation wraps). The **only** way to change the sim is `SimWorld.apply_command(cmd: Command)`; the sim reports change through `SimEvent`s drained per tick and read-only `SimView` accessors. **Flight, projectile and collision physics are our own** (CF kinematics, swept spheres, analytic terrain); Godot physics (Jolt) is not used in v1 at all (debris is kinematic and pooled; Jolt may serve presentation debris in v1.x behind a quality switch). AI runs **inside the tick through one hook** (`SimWorld.set_ai_hook(SimAiHook)`, implemented by `sim_ai`; `sim` never depends on `sim_ai`) and is **staggered**: each autopilot thinks every 10 ticks (3 Hz; 15 under the default budget profile and offline on web) and acts every tick on its cached plan, writing the entity's input slot through `CommandSink.drive`; the Commander bot thinks every 30 ticks in three slices of <= 0.7 ms. Pure steering controllers (`FlightController`, `LandingController`, `TerrainProbe`, `Assist`) live in `sim/steer/` so client prediction can run the auto-dock assist identically; an **assist substitution** sub-step sits between AI act and kinematics (R0 B.5 tick order). A per-match PCG32 RNG seeded by the server is the only randomness in the sim. Presentation uses **one pooled `Node3D` per visible unit or structure** (800 on Standard; 200 on Reduced/Lite/Low, the rest as `_Far` MultiMesh instances, 07 ART-A1) plus `MultiMeshInstance3D` pools for projectiles, debris and trails. **Threads:** none anywhere, with one exception: `src/app/offline_host.gd` may run `ServerSession.tick()` on a worker thread on non-web builds for offline Skirmish/Campaign (R0 C1-01); the web build stays single-threaded with Lite caps.

**Alternatives.** One Node per unit with `MultiplayerSynchronizer`: rejected; no quantisation, interpolation or prediction, linear per-node cost (R2 s5.4). Jolt rigid bodies for ships: rejected; untested single-thread web runtime, and realistic physics fights the CF model. Deterministic lockstep: rejected; floating-point determinism across phone, PC and browser is a hard target (R1 s2.3) and action flight needs sub-tick responsiveness.

**Rationale.** PA's proven client-server split (R1 s2.1) at 2-8 player scale, in the only language that reaches every platform.

**Consequences.** Spike S-SIM-1: 1,200 entities + 2,000 projectiles at 30 Hz in GDScript, with the real codec, interest, replay writer and time-sliced A*, run as 6 concurrent instances on the production host SKU, must fit p95 <= 25 ms per instance (the paper budget is 26.5 ms before the default cut rungs; R0 B.7). If it does not, the first native twins are the kinematics step and the collision hash (v1.1; Q6). The sim's public surface, including the append-only enumerations of R0 Part B.3, is frozen in `src/sim/MODULE.md` by task CONTRACT-0 before parallel lanes start; enum growth is a MODULE.md change, never an ADR (03 amendment 1 accepted).

### ADR-07 Networking model

**Decision.**
- **Authority:** the server owns all state. Clients send `Command`s (reliable) and `PilotInput` (unreliable, each packet carrying the last 3 ticks of input for loss tolerance).
- **Prediction:** the client predicts **only its possessed unit** with the shared `Kinematics.step_ship()` from its input buffer, reconciles on each authoritative state with a 100 ms smoothing window, and never predicts weapons' hits (muzzle flash is instant, damage waits for the server).
- **Interpolation:** everything else renders 100 ms behind the newest snapshot by interpolation between the last two states, extrapolating at most 100 ms on loss.
- **Interest management** in three tiers per client: **A** (possessed unit, its target, everything within 600 m: <= 40 entities, 30 Hz, 8-byte deltas), **B** (entities in the client's view cells and one ring, team-visible: <= 200, 15 Hz, 6-byte deltas), **C** (all other team-visible entities as blips: <= 1,000, 2 Hz, 4 bytes). A snapshot packet is <= 1,200 bytes; several per tick are allowed. A reliable **keyframe** of the client's whole interest set is sent on join, reconnect and stale ack; tier C is refreshed by a rolling round-robin of full records inside ordinary snapshots, never by a periodic burst (R0 C1-15). Gun slugs, flak shells and rail slugs are spawn events, not entities, on the wire.
- **Transports behind one interface** (`net/transport.gd`): `ENetTransport` (native clients, UDP), `WebSocketTransport` (web clients, `wss://` behind Caddy; also the fallback for native clients on hostile networks), `LocalTransport` (in-process queue for offline play), and from v1.1 `WebRtcTransport` (unreliable channels for web; `webrtc-native` on the server). The server polls all listeners each tick and wraps every peer in its own `Connection` id, as R2 s5.3 prescribes. `SceneMultiplayer`/RPC/`MultiplayerSynchronizer` are not used.
- **Topology:** **dedicated servers** (headless Godot, one process per match) for all matchmade play and online co-op. **Listen server** (a native client hosting with `LocalTransport` for itself and ENet/WS for others) for LAN and custom games only; no NAT traversal promise. **Offline Skirmish and Campaign run the same `ServerSession` in-process**; the client reads a `LocalSimView` of the in-process `SimWorld` directly (no snapshot encode/decode), and the shared `SimView` contract test keeps `LocalSimView` and `NetSimView` identical in behaviour (R0 C1-01). The predicted possessed unit is rendered from `Prediction.render_state(alpha)`, interpolated between ticks, so it never judders at 60 fps (R0 C1-07).
- **Resilience:** reconnect within 120 s receives a keyframe and resumes; the server tolerates a background-tab stall of 60 s before dropping a web client (R2 s3.1); clocks sync by tick number with a drift estimator.

**Alternatives.** WebSocket for everyone (simplest single transport): kept as fallback; rejected as the only transport because TCP head-of-line blocking hurts the possessed-unit feel on lossy mobile links. WebRTC for everyone: deferred to v1.1 pending spike S-NET-2. Peer-to-peer: rejected (cheating, browser constraints).

**Rationale.** PA's model (R1 s2.1) with Triplane-grade responsiveness only where it matters (the one unit you fly). Browser constraints are met on day one (R2 s3.4, R3 s4).

**Consequences.** Bandwidth budget per client <= 24 KB/s typical, 40 KB/s peak (Section 8). Spike S-NET-1 (ENet + WS listeners, 400 entities, 8 clients, 100 ms RTT, 3 percent loss) is a P0 gate. The protocol has a version and a content hash in `HELLO`; mismatches refuse the connection.

### ADR-08 Backend: accounts, matchmaking, lobbies, persistence

**Decision.** **Buy the identity and social layer, build the match layer.**
- **Nakama** (Apache-2.0, server v3.41.x, GDScript client) self-hosted on a Linux VPS with its Postgres: accounts (**v1.0: device/guest, email+password, Steam linking; Sign in with Apple and Google arrive in v1.1 with iOS**), friends, parties, lobby chat, matchmaker (keys: region, mode, input class, content hash; no rating bands until the first season patch), ratings recorded, player storage (cosmetics, settings, progression), server-side RPCs in TypeScript for entitlement validation, moderation and the **account deletion cascade** (R3 s7.1). Leaderboards, seasons and groups are v1.x (R0 C3-15).
- **FleetManager** (our own, TypeScript on Node, one small service): keeps a pool of **pre-started headless server processes on a fixed set of regional hosts** (EU-central first), answers Nakama's matchmaker callback with a host:port and a signed join token, collects match results, serves the moderation admin page, and exposes health. The v1 operations stack is deliberately small: Nakama + Postgres + FleetManager/FleetAgent + Caddy + Prometheus/Grafana, logs in journald with daily upload; Loki/Promtail are v1.x; a monthly restore drill and a runbook are launch deliverables (R0 C1-12). No Hathora, Unity Multiplay, Rivet or W4 Cloud (all dead or de-emphasised, R2 s11). Edgegap or GameFabric are evaluated only when per-match elasticity is needed.
- **TLS** by Caddy on each host, terminating `wss://` to the local WebSocket listeners; ENet listeners are exposed directly on UDP.
- **Persistence:** progression and entitlements server-authoritative in Nakama storage; local `user://` is a cache and holds offline saves (ADR-10); Steam Cloud mirrors offline saves on Steam (R3 s3) in v1.x.
- **Age band** (under 13 / 13-15 / 16-17 / 18+) stored in Nakama metadata from a neutral sign-up prompt and gating chat, analytics and purchases (R3 s7.3).

**Alternatives.** Fully custom backend: more control, far more work and compliance surface. Talo: lighter but lacks matchmaking and parties. Steam-only networking: partner-gated SDR, no mobile or web (R3 s3).

**Rationale.** Nakama covers the compliance-critical features (deletion, linking, moderation hooks) that R3 says must exist before login code is written; the match layer is small and ours.

**Consequences.** `src/platform/` wraps Nakama behind our own `Accounts`/`Social`/`Matchmaking` interfaces so the backend can be swapped. Guest play (no account) is allowed for offline Skirmish and Campaign and for web portal play, with an upsell to link an account; ranked requires an account. 04 owns the protocol between Nakama, FleetManager and game servers.

### ADR-09 Data-driven content, balance tables, modding stance

**Decision.** **JSON is canonical** for all gameplay definitions: ships, ground units, structures, towers, weapons, projectiles, doctrines, economy, match rules, modes, autopilot parameters, bot promises and profiles, map recipes, campaign missions, localisation strings. **Field names, file list and canonical values are frozen in R0 Part B.1 (02's descriptive naming scheme); 02 owns gameplay values, 03 owns `rules.json` (world constants) and the map recipe schema, 05 owns autopilot, order-rule and bot-profile files.** Files live in `godot/content/defs/*.json`, validated against JSON Schemas in `tools/schemas/` by `tools/validate_content.py` in CI and loaded at startup by `content/content_db.gd` into typed `RefCounted` `Def` classes (`ShipDef`, `StructureDef`, `WeaponDef`, `ProjectileDef`...). Doctrines are resolved once per match by the pure `ContentDB.resolve_for_doctrine()`; base defs are never mutated. Display names are derived (`unit.<id>.name`), never stored in defs. Presentation hints (mesh path, VFX ids, audio ids) live in the same def under a `presentation` key so a Haiku agent can wire a new unit without touching scenes. A SHA-256 **content hash** over the sorted defs (all `content/defs/*.json` except `sfx.json` and `vfx_prewarm.json`, with every `presentation` key stripped; `content/ui/**` and `content/locale/**` excluded) is part of the network handshake and the replay header. `.tscn`/`.tres` are used only for presentation prefabs and UI. **Modding:** data packs (JSON + assets in `user://mods/<id>/`) load in custom lobbies and offline play when every participant has the same pack hash; no script mods; matchmade play is stock only.

**Alternatives.** Godot `Resource` (.tres) for defs: editor-friendly, but diff-hostile, hard to validate outside Godot and awkward for Python tooling. Hard-coded constants: C&C's modding complaint (R1 s2.4).

**Rationale.** Agents at every tier can read, write and validate JSON with ordinary tools; schemas make Haiku edits safe; the hash makes mismatches explicit.

**Consequences.** Every numeric anchor in this document ends up in a def file, never in a script. A `defs` change is a content PR with a schema check and a bot-vs-bot balance smoke run (ADR-11).

### ADR-10 Replays, save games, spectating

**Decision.**
- **Replays** are **snapshot streams recorded by the server**: a header (protocol version, content hash, map recipe hash, players, seed), then all entities, unfiltered by interest, as 10 Hz deltas against the previous keyframe with a keyframe every 10 s, plus the full event stream, compressed with gzip. Target <= 20 MB per 30-minute 8-player match. Playback is a `ClientSession` fed from a file instead of a transport, with scrubbing to keyframes, free camera and possession-view follow. Input-replay is impossible because the sim is not cross-platform deterministic (ADR-03/06); no live rewind (PA's costs, R1 s2.1).
- **Spectating** is a `ClientSession` joined with the `spectator` role: all-seeing interest set, no command rights, 10 s delay in ranked. Eliminated players switch to this role only when their team has no Core left.
- **Save games** exist only for offline Skirmish and Campaign and for the host of a listen-server co-op: `SimWorld.serialize()` writes the full packed-array state, order and production queues, AI hook state, RNG state and tick number (about 200 KB) to `user://saves/` (3 manual slots + autosave every 5 minutes). Online PvP has no mid-match save; reconnection covers drops. Offline sessions also record `.pwr` replays to `user://replays/` (20-file cap); online replays are fetched through a signed URL RPC (R0 C2-25).

**Alternatives.** Deterministic input replays: smaller but require lockstep determinism. Video capture: not a replay.

**Rationale.** The snapshot codec already exists for networking; replays reuse it (R1 s3 item 18).

**Consequences.** The codec must be versioned; old replays are not guaranteed after protocol changes (a UI warning, not a crash). Replay recording costs the server about 25 KB/s of disk per match.

### ADR-11 Testing and verification strategy suited to AI agents

**Decision.** **gdUnit4 6.2.x is the single test framework.** Test layers, all runnable headless from a clean checkout after `godot --headless --import`:

| Layer | Location | What | Gate |
|---|---|---|---|
| Unit | `godot/test/unit/<module>/` | pure functions: sphere math, kinematics, codec round-trips, placement rules, A*, ContentDB | every PR, < 2 min |
| Sim integration | `godot/test/sim/` | scripted matches on a tiny test map: possess/release handoff, resupply economics, build radius, victory, Core Exposure | every PR, < 5 min |
| Net integration | `godot/test/net/` | server + N `LocalTransport` clients in one process; packet loss and reorder injection; prediction reconciliation bounds; fuzzed packets never crash the server | every PR |
| Bot-vs-bot soak | `godot/test/soak/` | 8 Commander bots, full map, 30 sim-minutes at `--fixed-fps`; asserts no NaN, no stall, p95 tick time, a winner exists, median match length in 18-32 min | nightly; 10 min version on PR |
| Perf benchmarks | `godot/test/perf/` | tick time at 1,200 entities, codec bytes per snapshot, A* expansions per ms, chunk build time; results appended to `perf/history.jsonl` | nightly on **one pinned self-hosted runner of the production host SKU**; fails only on > 20 % regression vs 7-day median there. GitHub-hosted jobs assert correctness only, plus a same-job base-vs-head A/B at 25 % (R0 C1-11) |
| Golden screenshots | `godot/test/golden/` | 12 fixed world scenes (`world/`) plus up to 8 UI scenes (`ui/`) and up to 8 art/night scenes (`art/`) rendered under Xvfb + Mesa llvmpipe (Compatibility), compared with a perceptual tolerance; goldens keyed by driver string | nightly; PR when `presentation/` or `ui/` changes |
| Content validation | `tools/validate_content.py`, `tools/validate_scenes.gd` | schema checks, dangling references, every `.tscn` instantiates | every PR |
| Device smoke | manual + CI artefacts | Android debug APK and web build booted to the main menu | release branch |

Agent rules: tests are part of the definition of done for every task; a task that changes a `MODULE.md` contract must update the contract's tests first; `godot -d` is never used without `--remote-debug tcp://127.0.0.1:0` (R2 s10.2 gotcha); the 10-minute headless soak in S-CI-1 settles the unverified stall report (R2 s10.6).

**Alternatives.** GUT: fine, but one framework keeps agent instructions short. Editor-connected MCP as the primary loop: deferred; the CLI works for every model tier.

**Rationale.** A headless-capable sim (ADR-06) makes most of the game testable without a GPU, which is exactly what agents have.

**Consequences.** Visual regressions are caught nightly, not per PR; presentation agents must attach a local screenshot to their PR description.

### ADR-12 Build, CI and release pipeline

**Decision.** GitHub Actions. Linux jobs use `barichello/godot-ci:4.7.2-stable`: import, tests, exports for **Linux dedicated server** (`dedicated_server` preset, textures stripped), **Windows x86_64**, **Linux x86_64**, **Web** (single-threaded, no extensions, Brotli-precompressed, size gate 20 MB), **Android** (AAB via Gradle, arm64-v8a only, target API 36, JDK 17, NDK r28b, keystore from secrets). A macOS runner image providing **Xcode >= 26** (verify that `macos-15` ships it, else `macos-26`) exports **macOS** and builds/signs the **iOS** Xcode project exported by the Linux job (R2 s12.2), weekly and on release branches. **Release scope (owner, 2026-10-10): v1.0 ships Windows via Steam (covering Steam Deck), Android via Google Play and web on itch.io and our own site. iOS, macOS, Linux native, Poki and CrazyGames are v1.1: their exports build in CI from day one, but store listing, QA, compliance artefacts and portal SDK work wait.** Export presets are committed in `export_presets.cfg`; secrets never are. Versioning `MAJOR.MINOR.PATCH+build`, with the content hash and git SHA shown in the main menu footer. Git LFS for `godot/assets/**` binaries. Server images are Docker (`debian:bookworm-slim` + the server export), deployed by `server-ops/` scripts.

**Alternatives.** Local-only builds: no reproducibility for agents. Self-hosted Mac: Open question Q10.

**Consequences.** Every lane's PR gets the same green/red; the web size gate is a hard fail (R3 s4 portal limits).

### ADR-13 Compliance by design (from R3)

**Decision.** Built before the first online build ships: account deletion endpoint with cascade (Nakama + FleetManager results + analytics ids) reachable in-app and from a web page; age band at sign-up gating chat, voice (none in v1), analytics and purchases; **text chat is team-only with quick-ping wheel**, message ids, report/block/mute and a moderation queue; no ad or tracking SDKs in any v1.0 build (portal SDKs are a v1.1 decision, 06 A2 deferred); client crash reporting without PII and an analytics event schema with an EU sink (R0 C2-24); pseudonymous analytics with EU hosting, off for under-13s; store-agnostic entitlement validation; no randomised paid items; Steam Deck baseline (controller-navigable UI, 9 px minimum text at 1280x800, 30 fps default) and WCAG 2.1 AA on web account pages; clean-room rule and no Triplane names (R1 s1.4). Privacy manifest and data-safety answers maintained in `docs/compliance/` by the platform lane.

### ADR-14 Agent development conventions

**Decision.** The repository is organised into **lanes** = modules (Section 9). Each module has a `MODULE.md` with: responsibility, allowed dependencies, public API with GDScript signatures, invariants, test entry points, and the model tier suggested for typical tasks. Conventions: `class_name` on every script; files <= 400 lines; one public class per file; no new autoloads without an ADR amendment (allowed autoloads: `App`, `ContentDB`, `Log`); every sim-affecting constant lives in JSON; commit messages reference the task id; agents never read Triplane source (R1 s1.4), never file upstream Godot issues or PRs (R2 s1.4), never add dependencies outside the allowlist. The dependency table of Section 9.2 is mirrored verbatim in `tools/deps.json`; the only cross-layer exception is the named list of `sim` public types that `input`, `ui`, `campaign` and `net` may reference (06 A1 accepted, R0 B.4). **Before any lane opens, task CONTRACT-0 commits the JSON schemas and `sim/MODULE.md` that encode R0 Part B.** **Tier guidance** (the roadmap doc will refine): Fable for cross-module design changes and ADR amendments; Opus for sim, net, planet renderer, Commander bot, and all reviews of those; Sonnet for features against a `MODULE.md`, UI screens, platform services, tools; Haiku for defs, schemas, docs, map recipes, test data, lint fixes, straightforward unit tests.

---

## 8. Budgets

### 8.1 Entity caps per match

| Entity kind | Standard (native online; PC/Deck offline) | Reduced (web client interest limit; mobile/web offline once S-WEB-2 passes) | **Lite** (single-thread offline on web and mobile until S-WEB-2 passes) |
|---|---|---|---|
| Player slots | 8 | 8 | 4 |
| Units per player (ships + ground) | 80 | 40 | 30 |
| Structures per player | 60 | 40 | 30 |
| Total units + structures | 1,200 (hard cap 1,280 slots live) | 640 | 240 |
| Live projectiles | 2,000 | 1,000 | 600 |
| Live wrecks | 200 | 100 | 60 |
| Visible entity mesh nodes (client) | 800 | 200 (+ `_Far` MultiMesh pools for the rest) | 200 (+ far pools) |
| Visible terrain chunks | 150 | 90 | 90 |

Unit caps are enforced by the sim (production blocks at cap) and surfaced in the UI (Brutal Legend's troop cap, R1 s2.2). Caps are per-mode data in `match_rules.json` (ADR-09), not code. Online matches always run Standard caps on the server; Reduced and Lite are offline-mode and client-side limits (R0 C1-01, C1-17; 07 ART-A1 accepted).

### 8.2 Client performance targets

Reference devices: **PC-mid** = GTX 1060 / Ryzen 5 2600 / 16 GB (2016-2018 class); **Steam Deck**; **Android-mid** = Snapdragon 695 class, 6 GB (2022 mid-range); **iOS-mid** = iPhone 11 (A13; **v1.1 target**, measured when the Mac arrives); **Web-desktop** = PC-mid in Chrome; **Web-mobile** = Android-mid in Chrome. Web `INITIAL_MEMORY` is 256 MB growing to 1 GB; web decoded audio <= 15 MB; the client's `ClientSession.tick` (decode + interpolation + prediction) is budgeted at 1.0 ms PC / 3.0 ms mobile-web per tick (R0 C1-20, C1-16, C1-23).

| Target | PC-mid | Steam Deck | Android-mid / iOS-mid | Web-desktop | Web-mobile |
|---|---|---|---|---|---|
| Frame rate | 60 fps at 1080p | 60 fps at 800p (30 fps minimum per Deck Verified) | 30 fps stable (60 on high tier) | 60 fps | 30 fps |
| Draw calls per frame | <= 1,500 | <= 1,000 | <= 400 | <= 800 | <= 400 |
| Triangles per frame | <= 1.5 M | <= 1.0 M | <= 400 k | <= 800 k | <= 400 k |
| Resident memory | <= 2 GB | <= 2 GB | <= 1 GB | <= 1 GB wasm heap | <= 800 MB |
| Install / initial download | <= 1 GB | <= 1 GB | <= 150 MB store download | <= 20 MB Brotli initial, map packs 4 MB each | same |
| Time to main menu | <= 10 s | <= 10 s | <= 8 s | <= 20 s on 20 Mbit/s (CrazyGames rule, R3 s4) | <= 20 s |
| Shader pre-warm | at load | at load | at load | at load | at load |

Asset budgets (07 enforces): Dart <= 600 triangles, Lancer/Hauler <= 900, Bomber <= 1,200, small structures <= 800, Shipyard/Refinery <= 1,500, Core <= 3,000; one 256^2 palette atlas shared by all units (2,048^2 remains the ceiling for a v1.x paint sheet); terrain chunk 2,048 grid triangles plus skirts; particles <= 2,000 live quads on mobile; the mobile draw-call budget of 400 is met with 200 entity mesh nodes plus far pools (07 s5.3).

### 8.3 Network budgets

| Direction | Typical | Peak | Notes |
|---|---|---|---|
| Server -> client | <= 24 KB/s (192 kbit/s) | <= 40 KB/s (320 kbit/s) | tiers A/B/C of ADR-07; snapshot packets <= 1,200 B |
| Client -> server | <= 2 KB/s | <= 4 KB/s | 30 Hz input with 3-tick redundancy + sporadic commands |
| Server egress per 8-player match | ~200 KB/s | 320 KB/s | ~2.6 Mbit/s peak |
| Playable latency | <= 150 ms RTT, 3 % loss | 250 ms RTT, 5 % loss degrades gracefully | prediction window 250 ms max |

### 8.4 Server budgets

| Resource | Budget |
|---|---|
| CPU | 1 dedicated vCPU per match; tick p95 <= 25 ms, p99 <= 33 ms at 1,200 entities and 8 clients, measured with the real codec and 6 concurrent instances on the production SKU. The per-step budget is the 03 s4.2 table as re-baselined in R0 B.7 (26.5 ms on paper before the default `sim_budget_profile` rungs 1-2, which bring it to ~24.2 ms) |
| RAM | <= 512 MB per match process |
| Disk | <= 25 KB/s replay write; replays retained 14 days |
| Host | 8 **dedicated**-vCPU / 16 GB host runs 6 concurrent matches plus Caddy (a shared-vCPU host runs 4); at most 6 PLAYING per host, the spare process is allocatable only while PLAYING < 6; ~EUR 60/month; first region EU-central (R0 C1-08, C1-22) |
| Startup | pre-warmed process pool; match ready <= 3 s after allocation |

---

## 9. Repository layout, module boundaries, key interfaces

### 9.1 Top-level tree

```
Planewar/
  README.md                 # what, how to run, lanes
  CLAUDE.md                 # agent conventions (ADR-14) and links to MODULE.md files
  .godot-version            # 4.7.2-stable
  .gitattributes            # LFS for godot/assets/**
  docs/                     # this plan: 00 (master plan, entry point)..10, backlog/, reviews/, research/, adr/ (amendments), compliance/
  godot/                    # the single Godot project: client, server and sim
    project.godot
    export_presets.cfg
    addons/                 # gdUnit4, nakama (allowlist only)
    src/
      core/                 # sphere math, ids, rng, log, config, result types
      content/              # ContentDB and typed Def classes (loads godot/content/defs)
      sim/                  # SimWorld and everything that changes game state
      sim_ai/               # autopilots, Commander bot, Adjutant
      net/                  # protocol, codec, interest, transports, sessions, prediction, replay
      server/               # headless match server app, fleet agent client
      presentation/         # planet renderer, entity views, VFX, audio emitters, decals
      camera/               # three-tier camera rig
      input/                # device -> intents (PilotInput, UI intents), input class, assists
      ui/                   # HUD, sidebar, alerts, globe map, menus, lobby, settings, a11y, i18n
      platform/             # accounts (Nakama), entitlements, saves, analytics, deletion, portal SDKs
      campaign/             # mission runtime: triggers, objectives, dialogue
      app/                  # boot, scene flow, mode orchestration
    scenes/                 # .tscn prefabs by domain (presentation/, ui/, app/)
    assets/                 # glb, textures, audio, fonts (LFS)
    content/
      defs/                 # JSON gameplay definitions (ADR-09)
      maps/                 # <map>/recipe.json + baked faces (LFS)
      campaign/             # mission JSON
      locale/               # strings
    test/                   # gdUnit4: unit/ sim/ net/ soak/ perf/ golden/
  server-ops/               # Dockerfile, Caddyfile, systemd units, fleet-manager/ (TypeScript), nakama/ (config, TS modules), deploy scripts
  tools/                    # Python: moonbake/, validate_content.py, schemas/, blender/ (export + MCP recipes), perf_report.py, replay_inspect.py, check_deps.py
  web/                      # HTML shell template, hosting config, portal adapters (itch, CrazyGames, Poki)
  .github/workflows/        # ci.yml (PR), nightly.yml, release.yml, ios.yml
```

### 9.2 Modules, responsibilities, allowed dependencies, suggested tier

Dependencies point downward only; `tools/check_deps.py` fails CI on a violation (it scans `preload`, `load`, type annotations and `class_name` references).

| Module | Responsibility | May depend on | Must never touch | Typical tier |
|---|---|---|---|---|
| `core` | `Sphere` (tangent frames, cube-face mapping, great-circle distance, parallel transport), `EntityId`, `Rng` (PCG32), `Log`, `Config`, `Result` | Godot built-ins only | Nodes, scenes | Opus (sphere math), Haiku (utilities) |
| `content` | `ContentDB`, `*Def` classes, content hash, schema-mirroring validation | `core` | sim, UI | Sonnet (loader), Haiku (defs) |
| `sim` | `SimWorld`, `EntityStore`, `Kinematics`, `Combat`, `Economy`, `Production`, `Build`, `Orders` (`sim/orders/`: `OrderSpec`, queues, rules), `ControlMachine` (`sim/control/`), **`sim/steer/`** (`FlightController`, `LandingController`, `TerrainProbe`, `Assist`: pure controllers written by the AI lane, usable by prediction), `Vision`, `Spatial`, `Pathing`, `Terrain` (height sampling), `Commands`, `SimEvent`, `AlertKind`, `SimView`, `LandingGrade` (`sim/scoring/`), abstract `SimAiHook` and `CommandSinkBase`, serialization | `core`, `content` | Nodes, `net`, `presentation`, `ui`, `sim_ai` | Opus |
| `sim_ai` | `AiDriver` (implements `SimAiHook`), `AiState`, brains per class, overlays, `CommanderBot` (difficulty profiles), `Adjutant` | `core`, `content`, `sim` (reads `SimView`, issues `Command`s and input slots via `CommandSink`, writes `ai_tag`) | anything above | Opus (bot), Sonnet (autopilots) |
| `net` | `Protocol`, `Codec` (quantisation/deltas, shared per-tick cache), `Interest`, `Transport` + implementations, `ServerSession`, `ClientSession`, `Prediction` (incl. `Assist` substitution and `render_state(alpha)`), `ReplayWriter/Reader`, `NetSimView` | `core`, `content` (hash), `sim` (`SimWorld`, `Command`, `PilotInput`, `Kinematics`, `Assist`, `SimView`, `SimEvent`, `CommandResult`, `Terrain` read) | presentation, UI | Opus |
| `server` | Match lifecycle (lobby -> load -> play -> end), bot slot filling, `ProtocolValidator`, `MatchConfig`, results reporting, fleet agent HTTP, admin commands | `core`, `content`, `sim`, `sim_ai`, `net`, `platform` (token validation only) | presentation, UI | Sonnet |
| `presentation` | `PlanetRenderer` (chunked LOD), sky/sun/earthshine, `EntityViewPool` (+ far pools), `ProjectileRenderer` (MultiMesh), VFX, decals, audio emitters, interpolation from a `SimView` | `core`, `content`, `sim` (`SimView`, `SimEvent` types, `Terrain` read), `net` (`NetSimView` type only) | writing to the sim, UI | Opus (planet), Sonnet (views, VFX) |
| `camera` | `CameraRig` tiers, transitions, roll damping, near/far adaptation, shake | `core`, `presentation` (read `ViewState`) | sim, net | Sonnet |
| `input` | Device detection, input class, `PilotInput` production, UI intents, assists, remapping | `core`, `sim` (**type `PilotInput` only**) | sim internals, net, presentation | Sonnet |
| `ui` | HUD, bomb sight, alerts, globe map, build sidebar, production queue, lobby, menus, settings, accessibility, localisation, chat UI, chatter feed | `core`, `content`, `input`, `camera`, `presentation` (read), `net` (`ClientSession` command API), `sim` (**public types only: `SimView`, `SimEvent`, `Command`, `CommandResult`, `PilotInput`, `AlertKind`, `OrderSpec`, `LandingGrade`, read-only `Terrain`**) | sim internals, sim_ai | Sonnet, Haiku (screens from spec) |
| `platform` | `Accounts`, `Social`, `Matchmaking`, `Entitlements`, `Saves`, `Analytics`, `Deletion`, `PortalSdk` (web; adapters v1.1) | `core` | sim, net internals | Sonnet |
| `campaign` | Mission runtime: triggers, objectives, scripted spawns, dialogue, briefing data | `core`, `content`, `sim` (commands/events/`SimView`, **`CommandSinkBase`**), `ui` (briefing widgets) | net internals, sim_ai | Sonnet, Haiku (mission JSON) |
| `app` | Boot, settings (`SettingsModel`), scene flow, mode orchestration (`match_controller.gd`; in-process server for offline in `offline_host.gd`, the only file allowed a `Thread`, non-web only; client for online), crash reporting | all | - | Sonnet |
| `tools/` | moon baker, validators, Blender export, perf reports, dependency checker | - | - | Sonnet, Haiku |
| `server-ops/` | infra as code, FleetManager, Nakama modules | - | - | Sonnet |
| `test/` | all test layers of ADR-11 | all | - | Sonnet, Haiku |

### 9.3 Runtime composition (who owns the loop)

- **Offline (Skirmish, Campaign):** `app` creates a `ServerSession` and a `ClientSession` in the same process joined by `LocalTransport` for commands and inputs. **The client reads a `LocalSimView` of the in-process `SimWorld` directly (no snapshot encode/decode)**; the `SimView` contract test keeps `LocalSimView` and `NetSimView` behaviourally identical. On native builds `app/offline_host.gd` may run `ServerSession.tick()` on a worker thread; on web everything runs on the main thread at Lite caps (R0 C1-01). Offline modes may pause and save (ADR-10).
- **Online client:** `app` creates a `ClientSession` over `ENetTransport` or `WebSocketTransport`.
- **Dedicated server:** `server/main.gd` creates a `ServerSession` with ENet and WS listeners, no presentation.
- **Tick driver:** `_physics_process` at `physics_ticks_per_second = 30` calls `ServerSession.tick()` and `ClientSession.tick()`; `_process` drives presentation interpolation and camera.

### 9.4 Key interfaces (signature level; `sim/MODULE.md` and R0 Part B supersede this listing where they differ; enums are append-only with frozen ordinals)

```gdscript
# ---- sim ----------------------------------------------------------------
class_name SimWorld extends RefCounted
func load_map(map: MapDef, seed: int, rules: MatchRules) -> Result
func add_player(slot: int, team: int, doctrine: StringName, kind: PlayerKind) -> void   # HUMAN | BOT | OPEN
func remove_player(slot: int) -> void
func set_ai_hook(hook: SimAiHook) -> void                                              # sim_ai attaches here; sim never imports sim_ai
func apply_command(cmd: Command) -> CommandResult                                      # ACCEPTED | REJECTED_*(reason)
func step() -> void                                                                    # advance exactly one tick (1/30 s); R0 B.5 order
func tick() -> int
func view() -> SimView                                                                 # read-only, valid until next step()
func drain_events() -> Array[SimEvent]
func serialize() -> PackedByteArray                                                    # includes the AI hook's opaque bytes
static func deserialize(bytes: PackedByteArray, content: ContentDB, hook: SimAiHook) -> SimWorld

class_name Command extends RefCounted
enum Kind { ORDER, BUILD, CANCEL_BUILD, PRODUCE, CANCEL_PRODUCE, SET_RALLY, POSSESS, RELEASE,
            REQUEST_POSSESS, HANDOVER, PILOT_INPUT, TOGGLE_AUTO_REPLENISH, SURRENDER,
            SET_ADJUTANT, DEBUG_SPAWN, DEBUG_SET }                                     # 0-15 frozen; append only (R0 B.3)
var tick: int; var player: int; var kind: Kind; var target: int                        # target = EntityId or 0
var payload: PackedByteArray                                                           # kind-specific, codec-defined (04 s2.5)

class_name PilotInput extends RefCounted   # one per tick for a possessed or AI-driven unit; 8 bytes on the wire
var thrust: float; var pitch: float; var yaw: float; var roll: float                    # [0..1], [-1..1] x3; towers: pitch/yaw = slew rates
var buttons: int                                                                       # bitmask: BOOST, BRAKE, FLIP, FIRE1, FIRE2, DOCK, RELEASE

class_name Kinematics   # pure, shared by server sim and client prediction
static func step_ship(s: ShipState, input: PilotInput, def: ShipDef, common: FlightCommonDef,
                      rules: RulesDef, terrain: Terrain, dt: float) -> ShipState
static func step_projectile(p: Vector3, v: Vector3, def: ProjectileDef, rules: RulesDef, dt: float) -> ProjectileState

class_name Build extends RefCounted
func can_place(player: int, def_id: int, cell: int, rotation: int) -> Build.Reject      # the one placement validator (13 reasons, R0 B.3)

class_name SimAiHook extends RefCounted                                                # abstract, lives in sim
func on_tick(tick: int, view: SimView, sink: CommandSinkBase) -> void

class_name SimView extends RefCounted   # implemented by LocalSimView (direct arrays) and NetSimView (replicated)
func alive(id: int) -> bool
func pos(id: int) -> Vector3;  func vel(id: int) -> Vector3;  func basis(id: int) -> Basis
func def_id(id: int) -> int;   func owner(id: int) -> int;    func team(id: int) -> int
func hp01(id: int) -> float;   func fuel01(id: int) -> float; func ammo(id: int) -> int; func bombs(id: int) -> int
func control_state(id: int) -> int           # AUTO | ORDERED | POSSESSED
func possessor(id: int) -> int               # player slot or -1
func ids_in_cell(cell: int) -> PackedInt32Array
func ids_near(p: Vector3, radius: float, mask: int) -> PackedInt32Array
func stockpile(team: int) -> Vector3         # ore, ice, power_ratio
func visible_to(team: int, id: int) -> bool
# plus the accessors of R0 Part B.5 (tick, boost_state, dock_state, service_progress, order_head, pending_order,
# production_queue, stockpile_cap, power_balance, unit_count, supply01, player_score, landing_grade_last, match_arc ...)

class_name SimEvent extends RefCounted
enum Kind { SPAWN, DEATH, HIT, BOMB_IMPACT, DOCKED, SERVICED, LAUNCHED, ORDER_DONE, ORDER_FAILED,
            POSSESSED, RELEASED, BUILD_STARTED, BUILD_DONE, STRUCTURE_LOST, LOW_POWER, ALERT, CORE_EXPOSURE, MATCH_END,
            CAP_REACHED, WRECK_SPAWNED, WRECK_SALVAGED, CEILING_RELEASE, HANDOVER, PLAYER_ELIMINATED,
            LOCK_ACQUIRED, LOCK_BROKEN, CAPTURE_PROGRESS, CAPTURED, SALVAGE_DELIVERED, LANDING, SHIELD_COLLAPSE,
            POSSESS_REQUESTED, CANISTER_DEPLOYED, CANISTER_COLLECTED }                 # 0-33 frozen; append only (R0 B.3)

# ---- net -----------------------------------------------------------------
class_name Transport extends RefCounted
signal connected(conn: int); signal disconnected(conn: int, reason: int)
signal packet(conn: int, channel: int, bytes: PackedByteArray)
func poll() -> void
func send(conn: int, channel: int, bytes: PackedByteArray, reliable: bool) -> void
func rtt_ms(conn: int) -> int
# channels: 0 control (reliable, ordered), 1 input (unreliable), 2 snapshot (unreliable), 3 events (reliable)

class_name ServerSession extends RefCounted
func _init(world: SimWorld, transports: Array[Transport], rules: MatchRules) -> void
func tick() -> void              # poll transports -> apply commands/inputs -> world.step() -> build snapshots per client
func add_bot(slot: int, difficulty: StringName) -> void

class_name ClientSession extends RefCounted
signal state_changed(state: int)      # CONNECTING | LOADING | PLAYING | RECONNECTING | ENDED
func _init(transport: Transport, local_player: int) -> void
func tick() -> void                   # send input, receive snapshots, reconcile prediction
func view() -> NetSimView             # for presentation, interpolated at render time via view().sample(alpha)
func send_command(cmd: Command) -> void
func set_pilot_input(input: PilotInput) -> void

# ---- presentation / camera / input ------------------------------------------
class_name EntityViewPool extends Node3D
func sync(view: SimView, render_time: float) -> void      # create/recycle nodes, interpolate, apply team colours
class_name CameraRig extends Node3D
enum Tier { CHASE, TACTICAL, COMMANDER }
func set_tier(tier: Tier, focus: Vector3, duration: float) -> void
func follow(entity: int) -> void
class_name InputRouter extends Node
signal pilot_input(input: PilotInput)                    # emitted once per sim tick while possessing
signal intent(kind: StringName, payload: Dictionary)     # SELECT, ORDER, BUILD_PLACE, ZOOM, POSSESS, RELEASE, PING...
func input_class() -> int                                # TOUCH | GAMEPAD | POINTER
```

**Contract notes.** `SimView` is the *only* way presentation and UI see the world; it must be identical in behaviour whether backed by local arrays or by replicated snapshots, which is enforced by a shared gdUnit4 contract test run against both implementations. `Command` is the *only* way anything mutates the world, including bots, campaign scripts and tests; AI-driven units receive their per-tick `PilotInput` through `CommandSink.drive`, which the sim refuses for POSSESSED entities. `Kinematics.step_ship` must be a pure function with no side effects and no `Node` access; the prediction tests execute it on both ends and assert bit-identical output on the same machine. All enumerations (`SimEvent.Kind`, `Command.Kind`, `OrderSpec.Kind`, `AlertKind`, `CommandResult.Code`, `Build.Reject`, `ReleaseReason`, control states, `LandingGrade.Grade`, `QuickPing.Kind`) are listed with frozen ordinals in R0 Part B.3; they grow by appending in `sim/MODULE.md`.

---

## 10. Glossary (canonical terms; use these words, not synonyms)

| Term | Meaning |
|---|---|
| **Entity** | Anything simulated with an `EntityId`: units, structures, projectiles, wrecks. |
| **Unit** | A mobile entity: ship (Dart, Lancer, Bomber, Scout, Hauler) or ground vehicle (Harvester, Siege Crawler). |
| **Structure** | A static placed entity (Core, Pad, towers...). **Tower** = a weapon-bearing structure (Autocannon Turret, Flak Battery, Missile Tower, Rail Lance); the Shield Projector is tower-class support. |
| **Core** | The Command Core, a team's HQ. Losing it eliminates its owner as a commander. |
| **Possess / Release** | Take / give up direct control of one entity. Possession is a control state, not a camera mode. |
| **Autopilot** | The per-class behaviour that drives an entity in AUTO or ORDERED state. |
| **Standing order** | The ORDERED-state order an entity holds; saved across possession as `saved_order`. |
| **Pending order** | An order issued to a possessed entity, applied on release. |
| **Adjutant** | Optional throttled bot that manages a human player's economy and replenishment. |
| **Commander bot** | The RTS AI that plays a full player slot. |
| **Chase / Tactical / Commander view** | The three camera tiers. "Commander view" is the orbital globe view; never call it "map mode". |
| **Pad** | Any landing/resupply point (Core pad, Pad structure, Hangar, Relay Station). **Dock** = the act of landing and being serviced. |
| **Sortie** | One flight from pad to pad. |
| **Resource node** | A fixed map feature that yields a resource: **Ore Field** (area) or **Cold Trap** (point). |
| **Stockpile** | A team's stored Ore or Ice. **Power** is a rate, not a stockpile. |
| **Supply network** | Pylon-carried ammo/power feed to towers. |
| **Build radius** | The disc around a Core/Outpost/Pylon where placement is legal. |
| **Datum** | The R = 6,000 m reference sphere. **Altitude** = distance from the core minus R. |
| **Deck / Low / High / Fade / Ceiling** | The altitude bands of Section 5.3. |
| **Terminator** | The day/night boundary; the equator in matchmade maps. **Noon Pole / Midnight Pole** = subsolar / antisolar points. |
| **Earthshine** | The night-side ambient light. |
| **CF kinematics** | The curved-flat flight model of Section 3.1.1. |
| **Tick** | One 1/30 s sim step. **Snapshot** = a per-client state packet; **keyframe** = a full snapshot. |
| **Interest tier A/B/C** | Per-client replication detail levels (ADR-07). |
| **Cell** | A cube-face grid square at one of the four resolutions of ADR-05. |
| **Def** | A JSON content definition and its typed GDScript class. |
| **Doctrine** | A player's chosen stat-modifier package (Vanguard, Bulwark, Foundry). |
| **Core Exposure** | The overtime rule (30:00 in the long-form modes; per-mode timers in `modes.json`, e.g. 20:00 in `pvp_1v1`). |
| **Lane** | A module owned by one agent task stream. |

---

## 11. Open questions for the owner (with defaults so work proceeds)

| # | Question | Default used until answered |
|---|---|---|
| Q1 | Which title? (Section 0.2) | Codename PLANEWAR internally; "Regolith" is the leading candidate pending a clearance search. |
| Q2 | Business model: premium on PC/Steam and a free mobile/web build with a one-time "full unlock" IAP and cosmetics? Or premium everywhere? | Premium (about EUR 15-20) on Steam; mobile free with offline Skirmish + Campaign chapter 1, one-time unlock IAP for the rest; web free as a funnel (Skirmish vs AI and unranked online). No randomised paid items anywhere. |
| Q3 | Shared team economy (one stockpile per team) vs per-player stockpiles with transfers? | Shared team stockpile and team-shared production queues. |
| Q4 | Campaign scope for v1? | 8 missions (about 4-6 hours), one faction's story, mission 1-3 are the tutorial; moving-sun rule allowed. |
| Q5 | Keep ground combat units (Siege Crawler) in v1? | **Answered 2026-10-10: yes.** Siege Crawler and Rail Lance stay in v1 (`status: core`); only the Storage Silo is cut. |
| Q6 | Allow any native code (GDExtension) in v1 if GDScript misses the server tick budget? | No native code in v1; apply the `sim_budget_profile` cut ladder (rungs 1-2 are the default) and reduce entity caps before anything else; native twins for `Kinematics` and `Spatial` are scheduled for v1.1. |
| Q7 | First server region and expected launch population? | EU-central, one 8 vCPU host; bots guarantee match starts at any population. |
| Q8 | Chat scope: team text + pings only, no all-chat, no voice? | Yes (compliance-driven, ADR-13); all-chat as a custom-lobby option later. |
| Q9 | Moving sun available in matchmade play as a "rotating moon" playlist? | No; custom/campaign only. |
| Q10 | Mac access for iOS: GitHub-hosted macOS runners only, or a physical Mac mini? | iOS is v1.1. GitHub-hosted runners (Xcode >= 26 image) keep the iOS export building from day one; a physical Mac (mini class) is acquired before the first v1.1 iOS performance milestone, not at TestFlight (R0 C1-14). |
| Q11 | Open-source anything (tools, protocol)? | Everything proprietary; `tools/` may be MIT later. |
| Q12 | Free-for-all in matchmade play? | Teams only in matchmade; FFA in custom lobbies. |
| Q13 | Ranked at launch, or unranked quick match with hidden MMR until population allows? | Quick match (`pvp_1v1`, `pvp_2v2`, `pvp_team`) with ratings recorded but not used for matching at launch; matchmaking keys are region, mode, input class and content hash; visible ranked ladder with rating bands in the first season patch. The auto-economy Adjutant is allowed in quick match and off in the ranked ladder. |
| Q14 (new) | Odd player counts: fill with bots to the next even count on the 8 main slots (the 24-slot scheme is withdrawn)? | Yes (R0 OQ-R0-1). |
| Q15 (new) | Portal ad SDKs for Poki/CrazyGames (06 A2)? | Decided at v1.1 planning; until then no ad or tracking SDK in any build and `break_allowed()` returns false. |
| Q16 (new) | Supply Canister (08 SL-5) ships in v1 only after the scope gate (S-SIM-1, S-WEB-2, S-FLIGHT-1 green and the 1v1 vertical slice complete); if the gate opens late it slips to v1.1 without a new decision? | Yes (R0 OQ-R0-6). |

---

## 12. Briefs for downstream documents 02-08

All seven documents are written in parallel against this spine. Each must open with a "Decisions inherited from 01" list, may refine *(anchor)* numbers within their tolerances, and must file anything that contradicts a non-anchor decision as an "ADR amendment request" section at its end rather than silently changing it. Cross-document dependencies are resolved by referencing this document, not each other.

### 02 - Game design document (`docs/02-game-design.md`)

Must cover: full stat tables for every unit, structure, tower, weapon and projectile in Section 6 (HP, cost in Ore/Ice, build/production time, power draw, speed, turn rates, ranges, damage distributions, fuel, cargo, sensor radius, altitude envelopes), using the anchors of Sections 3 and 5.2 as starting values; the three Doctrines fully specified; the economy as a spreadsheet-grade model (income per Harvester trip, Ice extraction rates, power curves, sortie costs, expected stockpile curves for a 24-minute match); the tech gating ("tech tree" is shallow by design: Core -> Pylon/Solar/Refinery -> Shipyard/Vehicle Bay/towers -> Outpost/Reactor/Shield/Hangar -> Rail Lance/Bomber); build radius and placement rules; resource node layouts for the three v1 maps derived from Section 5.6; victory, elimination, Core Exposure and the 40:00 hard end; match-arc timing targets with measurable checkpoints (first Dart airborne by 0:45 with the pre-built Shipyard, first Outpost by 6:00 median); mode rules for Online PvP (quick match `pvp_1v1`, `pvp_2v2`, `pvp_team`; custom to 4v4), Skirmish, Co-op (2-4 humans + bots vs bot team), Campaign (8 missions, objectives, which mechanics each teaches); bot difficulty tiers as player-facing promises; anti-snowball and comeback (wreck salvage values, cap pressure); the possess/release player-facing rules from Section 4 as game rules; scoring, medals, cosmetic progression; balance-test plan hooks (which soak-test metrics prove balance). Must respect: the CF flight model and all Section 3.1 rules; two stockpiles plus power; shared team economy (Q3 default); static terminator and equatorial starts; the roster of Section 6 as amended (Siege Crawler and Rail Lance are v1, the Storage Silo is cut; may not add units without an amendment); entity caps of Section 8.1 including the Lite profile; the def field names and canonical values of R0 Part B.1; fair-PvP rules of Section 3.4; everything numeric lands in JSON defs (ADR-09).

### 03 - Technical architecture (`docs/03-technical-architecture.md`)

Must cover: the Godot project setup (project.godot settings including the warning list, physics tick 30, Jolt selected but unused in sim, renderer Compatibility, export presets per platform); the `core` sphere math spec (equal-angle cube-face mapping with neighbour tables, tangent frames, parallel transport formula, great-circle distance); the sim data model (SoA layout, EntityId, slot allocation, component sets per entity kind), the tick order (inputs -> commands -> AI think slice -> kinematics -> projectiles/collision -> combat -> economy/production/build -> vision -> events), the CF kinematics equations with all constants named, the collision scheme, terrain height sampling; the planet renderer design (quadtree, chunk pooling, per-frame budgets, horizon culling, adaptive near plane, earthshine lighting, biome material, LOD for structures with visibility ranges, MultiMesh pools); the moon baker tool spec (recipe JSON schema, feature stamping, output formats, CI integration); the content pipeline (JSON schema -> ContentDB -> Defs; glTF import settings); performance plan against Section 8 with profiling methodology and the S-SIM-1, S-WORLD-1, S-NAV-1 spike definitions; quality tiers for mobile (what scales); memory plan; the web build specifics that touch architecture (single thread, pack streaming, no WorkerThreadPool); the `tools/check_deps.py` rule set; a risk register. Must respect: ADR-01 to ADR-06, ADR-09, ADR-11, ADR-12; the budgets of Section 8; the module map and interfaces of Section 9 (may add detail, may not rename or re-layer).

### 04 - Networking and backend (`docs/04-networking-and-backend.md`)

Must cover: the wire protocol (message catalogue with field layouts and byte sizes, channels, versioning, content hash handshake, join tokens); the snapshot codec (per-cell quantisation of position to 3x u16, smallest-three orientation, i8 velocities, u8 hp/flags; delta encoding against acked baselines; tier A/B/C schedules; keyframes); interest management rules; input redundancy and tick synchronisation; prediction and reconciliation for the possessed unit including the handoff moments (possess ack, release, death, hand-over); interpolation/extrapolation policy; loss/latency simulation harness and the S-NET-1/S-NET-2 spike definitions; the transport implementations (ENet, WebSocket behind Caddy, Local, WebRTC roadmap) and the dual-listener server loop; reconnect and background-tab tolerance; dedicated server lifecycle and the FleetManager API (allocate, heartbeat, result, drain); Nakama deployment, auth providers, account linking, matchmaking keys (region, mode, skill band, input class, party leader rule), parties and lobbies, leaderboards, storage schema for progression and cosmetics; the account-deletion cascade; chat moderation data flow; anti-cheat posture (server authority, command validation, rate limits, replay-based review); hosting topology, TLS, ports, cost estimate for the first host; observability (logs, metrics per match); replay file format (ADR-10) and spectator role. Must respect: ADR-06, ADR-07, ADR-08, ADR-10, ADR-13; Section 8.3-8.4 budgets; the `Transport`, `ServerSession`, `ClientSession`, `Command`, `PilotInput` signatures of Section 9.4; GDScript only, no SceneMultiplayer/RPC/synchronizers; web constraints of R2 s3.

### 05 - AI, autonomy and control (`docs/05-ai-autonomy-and-control.md`)

Must cover: the control-state machine (AUTO/ORDERED/POSSESSED) with every transition and the safety handoff of Section 4.4 as pseudocode; the order vocabulary and completion/failure conditions; per-class autopilots of Section 4.3 as behaviour specs (sensing inputs from `SimView`, decision cadence 3 Hz, steering model for CF kinematics including terrain avoidance by height-field lookahead, formation/escort behaviour, the return-to-pad and landing routine as the most-tested behaviour, Hauler ferry/tow logic, Harvester mining cycle with flee rules, tower target priority and altitude envelopes); the Commander bot (economy opening book, expansion logic, threat assessment, production mix, tower placement heuristics, raid and siege planning; bots never possess, they only issue orders; difficulty tiers defined by decision cadence, information handicaps and command-rate caps, never by stat cheats); the Adjutant as a restricted Commander bot; team-shared command conflicts (who wins when two humans order the same unit: last command wins, with a 1 s UI echo); bot behaviour as a fill-in for disconnected players; testability (scripted scenario suite, bot-vs-bot soak metrics, autopilot unit tests with recorded situations); performance budget for AI inside the 25 ms tick. Must respect: pillar P1; Section 4 entirely; ADR-05 pathing (own A* on the 6x256^2 grid, no NavigationServer3D); ADR-06 staggering; AI acts only through `Command`s and reads only `SimView`.

### 06 - Platforms, input and UX (`docs/06-platforms-input-ux.md`)

Must cover: input schemes for touch (VirtualJoystick from Godot 4.7, one- and two-finger selection idioms from R1 s2.3, no modifier keys), gamepad (Steam Deck Verified rules from R3 s3) and pointer, all producing the `PilotInput`/intent contract of Section 9.4; input-class detection and the assist tiers of Section 3.1.6; the three-tier camera spec (transitions, head-up roll damping, focus rules, PiP home window, alert tap-to-jump, orbit limits, near/far adaptation hooks); HUD (horizon on a sphere, bomb sight, fuel/ammo/bomb/HP, threat indicators, "piloted by" badges, uplink-fade warning, landing guide); Commander-view UI (globe, fog ghosts, alerts feed, production sidebar sized for 18 buttons without scrolling per R1 s2.4, build placement with validity feedback, control groups and rally points); menus, lobby (doctrine pick, input-class notice, party leader rule), settings, accessibility (colour-blind-safe team palettes with shape cues, text scaling, 9 px minimum at 1280x800, remapping, subtitles, reduced motion); localisation plan (English first, Finnish second); onboarding (campaign-as-tutorial beats, first-session length <= 15 minutes); web specifics (portal SDK adapters, autoplay audio unlock on first input, fullscreen/pointer-lock from input callbacks, user:// try/catch, background-tab reconnect UX, 20 s to gameplay); mobile specifics (safe areas, battery/thermal-friendly quality tiers, session resume); Steam specifics (Deck, Cloud files split by change frequency, Input glyphs); store compliance UX (age prompt, account deletion in settings, report/block). Must respect: pillar P4/P5; Section 4.1; Section 8.2 targets; ADR-02 (Compatibility only); ADR-13; R3 s7 architecture requirements 9-12 and 16.

### 07 - Art, audio and content pipeline (`docs/07-art-audio-content.md`)

Must cover: the art bible for flat-shaded low-poly on Compatibility (palette atlas, team-colour masks as emissive, silhouette rules per class, scale chart with the 12 m Dart as reference, readability at Chase/Tactical/Commander distances, night-side earthshine look); the procedural moon look (biome colour ramps, crater and rille treatment, boulder props, the Solar Plateau and Cold Trap visual language, horizon limb, skybox with Earth visible as the earthshine source); the Blender-MCP asset workflow (agent-driven modelling recipes, naming, glTF export settings with LOD generation at import, triangle budgets of Section 8.2, validation script, how a Haiku agent adds a variant); VFX on Compatibility (GPU particles without trails, MultiMesh projectiles, bomb impacts, shield domes, explosions, exhaust; pre-warm list); UI art direction and iconography (shape-coded team and class icons); audio design (vacuum-appropriate stylisation, mix buses, web Sample-mode limits from R2 s3.3, music states for the match arc, alert sounds as information); the content inventory for v1 with counts (ships, structures, props, VFX, SFX, music tracks, three maps) and a production estimate per asset class; the map recipe authoring guide for the moon baker; naming conventions for assets and defs; the IP rules (no Triplane assets or echoes). Must respect: pillar P4; ADR-02; ADR-04 (baked faces, visuals-only detail); Section 5.4-5.6; Section 6 roster; Section 8.2 asset budgets; names in Sections 6 and 10 are placeholders that 07 may rename with one cross-reference table.

### 08 - Feature ideas (`docs/08-feature-ideas.md`)

Must cover: a ranked backlog of new feature proposals, each with the pillar it serves, a one-paragraph design, cost tier (S/M/L), risk, and the earliest release (v1, v1.x, v2); must evaluate at least these seeds from this document: the Barge mobile pad, wreck towing and salvage markets, the Relay Station capture rules, moving-sun mechanics for campaign/custom, terrain line-of-sight in v1.x, Helium-3 as a late rare resource, picture-in-picture multi-view, commander supply drops onto the ship you fly (R1 s3 item 5), pilot combo scoring (Luftrausers), a manual-landing scoring system, a kill-cam from replays, spectator and caster tools, daily challenges built from the campaign mission runtime, player-authored map recipes via the baker, cosmetics that survive the no-pay-to-win rule, and accessibility features that double as new play styles (auto-throttle "cruise" mode). Must respect: nothing here may require a change to ADR-01 to ADR-08 for v1; ideas that do are labelled v2 and list the ADR they would amend; no randomised paid items; no avatar.

---

## Appendix A. P0 spikes (consolidated; owner tier Opus unless noted)

Execution order: S-CI-1 first; **S-FLIGHT-1 immediately after, on a flat-shaded icosphere with a stub pad and no renderer or economy (TA-04/05/12 only), before any downstream lane opens** (R0 C3-03); then S-SIM-1 and S-WORLD-1 in parallel; then S-NAV-1, S-WEB-1, S-WEB-2, S-NET-1, S-BACKEND-1. Gate CONTRACT-0 (schemas + `sim/MODULE.md` from R0 Part B) sits between S-CI-1 and the lanes.

| ID | Spike | Pass criterion | Blocks |
|---|---|---|---|
| S-FLIGHT-1 | CF kinematics prototype (`step_ship` with the speed-scaled lift law and its A/B switch) on an R = 6,000 icosphere with Chase camera stub, straight-line gun with targets at 200-800 m, bomb with impact marker, **tail-down pad landing**, render-time interpolation at 60 fps; keyboard + gamepad + touch; live tuning panel | Three novice testers land within 10 minutes; < 20 % of landing attempts in minutes 5-10 crash; a mouse tester lands within 15 attempts; co-altitude gun targets at 200-800 m are hit when aimed; cruise AoA <= 6 degrees reported; "feels like a plane with gravity" median >= 4/5; tuned values stay inside anchors or a refinement is filed to 02 | 02 anchors, 05 steering, 06 input layouts, 07 ship art beyond the Dart, 04 beyond the codec spike |
| S-SIM-1 | Headless `SimWorld` with 1,200 entities, 2,000 projectiles, staggered autopilots at 30 Hz, GDScript only, **with the real snapshot codec, interest, replay writer, time-sliced A* and projectile-terrain test**; run on the dev box and as 6 concurrent instances on the production host SKU | p95 tick <= 25 ms and p99 <= 33 ms per instance on the production SKU with the default budget profile | ADR-06, Q6, 03 s4.2 |
| S-WORLD-1 | Cube-sphere chunked LOD at R = 4/6/8 km, 1,024^2 faces, texel-index mesher vs GPU vertex-displacement variant, adaptive near plane, Compatibility renderer, PC + Android-mid + web; z-fighting scenes Z1-Z8 (Z8 = structures across a cube edge) | 60/30/30 fps; no visible z-fighting at Chase and Commander tiers; boost path (160 m/s at 30 m AGL, 60 s) on web-mobile and Android-mid shows no hole > 1 s within 400 m and <= 1 frame > 50 ms per 10 s | ADR-04, Section 8.2, 03 s13 tier values |
| S-NET-1 | Dual-listener server (ENet + WS), tiered codec with rolling tier-C refresh, 8 clients of which **at least 2 are real browsers** (Chrome desktop, Android Chrome), 400 entities, netem TARGET and BAD | <= 30 KB/s per client; possessed-unit reconciliation error p95 < 1 m at 150 ms RTT; browser main-thread stalls > 100 ms counted; decides whether `s_transport` enters ranked tickets | ADR-07 |
| S-NET-2 | WebRTC `create_server` with webrtc-native on Linux, browser client, unreliable channel | works end to end in Chrome, Firefox, Safari | v1.1 transport |
| S-NAV-1 | Time-sliced A* on the 6x256^2 grid with route cache vs `AStar3D`; 120 ground units re-pathing every 10 s | amortised <= 0.5 ms per tick; worst single query completes within 30 ticks; cache hit rate >= 80 % on harvester loops; zero correctness failures | ADR-05 |
| S-WEB-1 | Single-threaded web export of S-WORLD-1 with 200 ships; measure wasm + pack size, wasm compile time on web-mobile, boot on a 3 GB Android device, time to gameplay | <= 20 MB Brotli, <= 20 s on 20 Mbit/s (Mission 1 first beat within 10 s), 30 fps Android-mid Chrome, boots with 256 MB initial heap | Section 8.2 |
| **S-WEB-2 (new)** | In-process offline skirmish: `ServerSession` + `ClientSession` (`LocalSimView`) + renderer + 1/3/7 Normal bots on web-desktop, web-mobile and Android-mid native (iPhone 11 in v1.1) at Lite and Reduced caps | web-desktop 1v1 at Reduced caps p5 >= 45 fps; web-mobile 1v1 at Lite p5 >= 25 fps; Android-mid native 1v1 for 25 minutes at 30 fps without a tier downshift; sets the final Lite cap values | Section 8.1 Lite column, Q2 web funnel, offline mode defaults |
| S-CI-1 | Clean-checkout CI: import, gdUnit4, exports (Linux server, Windows, Web, Android debug; macOS/iOS weekly), 10-min headless soak, Xvfb screenshot, web size gate, pinned perf runner | green; soak slope of per-minute p95 < 2 % per minute; PR pipeline <= 15 minutes | ADR-11, ADR-12 |
| S-IOS-1 (Sonnet; **v1.1**) | Export Xcode project from Linux CI, build and sign on a macOS runner with Xcode >= 26, upload to TestFlight | build uploaded; `PrivacyInfo.xcprivacy` present; 10-minute device frame-time log collected | ADR-12 (v1.1) |
| S-BACKEND-1 (Sonnet, Opus review; 5 agent-days) | Nakama + FleetManager + one game host behind Caddy; browser and native client join the same match; moderation admin page; `pg_dump` restore drill | both clients in one match with WSS and ENet; result row written with verified hash; restore completes within RTO 2 h | ADR-08 |

## Appendix B. Research facts this document leans on most

- Web export: Compatibility/WebGL2 only, wasm32, single-threaded default, no raw UDP/ENet, WebSocket client + WebRTC only (R2 s2-3; R3 s4).
- C# cannot export to web; Android/iOS C# experimental; 4.8 moves to .NET 10 (R2 s4.1).
- float32 precision bands (R2 s7.1); double builds have no official templates (R2 s7.2).
- NavigationServer3D single up-vector (R2 s9.1).
- `SceneMultiplayer` takes one peer; synchronizers lack quantisation/prediction (R2 s5).
- Hathora and Unity Multiplay are dead; Nakama is maintained (R2 s11).
- Store rules in force: iOS 26 SDK, API 36, account deletion both stores, UGC moderation, no loot boxes advisable (R3 s1-2, s6).
- Triplane Turmoil: GPLv3 code and assets, trademarked name; clean-room rule (R1 s1.4; R3 s6.7).
- Design lessons: automatic layer is the product (Hostile Waters vs Carrier Command), server-sim thin clients with interest management (Planetary Annihilation), C&C economy and sidebar, head-up camera on spheres (Mario Galaxy 2), gravity-and-fuel skill (Thrust, Lunar Lander) (R1 s2-3).

---

## Amendment log (v1.1, 2026-10-10)

Each entry names the register row (`docs/reviews/R0-resolution-register.md`) that authorises it. Owner decisions are marked OWNER.

| # | Section changed | Change | Register ID |
|---|---|---|---|
| 1 | Header | Status v1.1; register named as binding; change policy notes frozen enumerations and contracts. | R0 Part 0, C1-10, C2-03 |
| 2 | s2 O5 | R = 6,000 m confirmed; 1v1 bases 90 degrees apart. | OWNER O-1, O-5 |
| 3 | s2 O10 | v1.0 platforms Windows/Steam (Deck), Android, web; iOS, macOS, Linux native, Poki, CrazyGames v1.1. | OWNER O-3, C3-16 |
| 4 | s3.1.1 item 2 | Parallel transport applies to ships, bombs, siege shells and rockets; slugs, flak and rail slugs fly straight world-frame lines. | C1-03, 03 amendment 4 |
| 5 | s3.1.1 item 5 | Speed-scaled vertical grip (`k_up_eff`, per-ship `k_up` and `k_up_flight`, `rules.lift_model`). | C1-04(a) |
| 6 | s3.1.3 Guns | Straight-line slug sentence; straight-line lead solvers. | C1-03 |
| 7 | s3.1.3 Flak | Autocannon envelope -200..+400 m relative. | 02 AR-2 |
| 8 | s3.1.4 | Tail-down powered landing rule (thrust axis within 25 degrees of the pad normal; 8 / 15 m/s); every ship hovers; tail legs; launch along the pad normal; landing grades ACE..AUTO without banking; repair bonus for FAIR+; Supply Canister exception (40 % fuel, 50 % ammo in flight). | OWNER O-2, O-7; C1-04(b), C2-10, C3-02, C3-13, 08 A-1 |
| 9 | s3.2 Refining | Storage Silo cut; Core 3,000 / 800, Refinery +1,500 / +500, Outpost +250 / +100. | OWNER O-4, C3-14 |
| 10 | s3.2 Manufacturing | Pre-built start kit (Core, Refinery, Shipyard, Vehicle Bay, Harvester; 800 Ore / 300 Ice); queue max 5; owner-only cancel; 2:00 share lock. | C3-01, C3-08, C2-27 |
| 11 | s3.2 Building | Outpost presence-and-spacing rule replaces the radius rule for Outposts. | 02 AR-1 |
| 12 | s3.3 arc table | Open phase checkpoints (Dart by 0:45, Core integrated shield to 8:00); Exposure adds 125 % bomb damage on Cores; per-mode Exposure and hard-end timers. | C3-01, C3-05, C3-19 |
| 13 | s3.4 | Three launch queues (`pvp_1v1`, `pvp_2v2`, `pvp_team`); ratings recorded, not used for matching until the first season. | C2-16, C3-15 |
| 14 | s4.3 | Siege Crawler kept; tower priority list from `towers.json`; Silo removed from the passive list; Adjutant via `SET_ADJUTANT`; `adjutant_economy` allowed in quick match with the "Auto economy" tag. | OWNER O-4, O-6; C2-15, C3-07, 05 AR-1 |
| 15 | s5.1 | R fixed by the owner; S-WORLD-1 radius variants are renderer tests only; slot spacing fixes small-count travel time. | OWNER O-1, C3-04 |
| 16 | s5.2 table | R fixed; slot longitude row; 1v1 at 90 degrees; antipode note. | O-1, O-5, C1-09 |
| 17 | s5.7 | Slot k at longitude 22.5 + 45 k; subsets 2 -> [0, 2], 4 -> [0, 2, 4, 6], 6 -> [0, 1, 2, 4, 5, 6], 8 -> all; 24-slot scheme withdrawn; odd counts bot-filled; team blocks restated. | C1-09, OWNER O-5, C3-04, OQ-R0-1 |
| 18 | s6.2 | Core: pad 12 m, storage 3,000 / 800, integrated shield to 8:00, pre-built kit; Outpost storage and presence rule; Storage Silo row deleted; Refinery storage; pad radii; Shipyard and Vehicle Bay pre-built; Rail Lance kept (1,500 m/s slug); Relay Station contest radius 300 m. | C3-05, 02 AR-1, OWNER O-4, C2-37, C2-20 |
| 19 | s6.3 | Siege Crawler kept; `a_thrust` per ship (Bomber 14, Hauler 15; minimum 2 g); rigid tow tether. | OWNER O-2, O-4; C3-17; R0 B.1 |
| 20 | ADR-01 | Jolt not used anywhere in v1. | 03 amendment 2 |
| 21 | ADR-03 | +X is the centre of face 0; slot 0 at longitude 22.5; Geodetic row; R fixed; consequence rewritten. | C1-09, O-1 |
| 22 | ADR-04 | Chunk = 2,048 grid + 256 skirt triangles; one-build-per-3-frames rule; texel-index mesher; GPU displacement variant in S-WORLD-1. | 03 amendment 3, C1-06 |
| 23 | ADR-05 | Placement rules add vision/enemy-radius checks and the Outpost exception; `Build.can_place` is the one validator; time-sliced A* with route cache. | 02 AR-1, C2-12, C1-05 |
| 24 | ADR-06 | No Jolt; AI through `set_ai_hook`; `sim/steer/` pure controllers; assist substitution sub-step; 200 mesh nodes + far pools on Reduced/Lite; one `Thread` exception in `app/offline_host.gd`; S-SIM-1 with real codec on the production SKU and 6 instances; enum growth via MODULE.md; CONTRACT-0. | C1-01, C1-02, C1-17, C2-04, 03 amendment 1, 07 ART-A1, C1-10 |
| 25 | ADR-07 | Rolling tier-C refresh instead of 10 s bursts; slugs/flak/rail as spawn events; offline `LocalSimView`; `Prediction.render_state(alpha)`. | C1-15, C2-35, C1-01, C1-07 |
| 26 | ADR-08 | v1.0 auth = device, email, Steam (Apple/Google v1.1); matchmaking keys without rating bands; leaderboards/seasons/groups v1.x; minimal ops stack, moderation admin page, restore drill, runbook. | C3-15, C1-12 |
| 27 | ADR-09 | Field names, file list and values frozen in R0 B.1 with 02's naming; ownership split 02/03/05; `ProjectileDef`; pure doctrine resolution; derived display names; content-hash scope. | C2-01, C1-10, C2-33, C2-34 |
| 28 | ADR-10 | Saves include AI hook state, 3 manual slots; offline replays to `user://replays/`; online replay download via signed URL RPC. | C2-07, C2-25 |
| 29 | ADR-11 | Perf gates only on a pinned production-SKU runner; GitHub jobs correctness + 25 % A/B; golden set 12 world + 8 UI + 8 art. | C1-11, C2-30, 06 A3 |
| 30 | ADR-12 | Xcode >= 26 runner image; v1.0 release scope Windows/Steam, Android, web; v1.1 platforms build in CI only. | C1-14, OWNER O-3 |
| 31 | ADR-13 | No ad/tracking SDK in any v1.0 build (06 A2 deferred to v1.1); crash reporting and analytics schema named. | 06 A2, C2-24 |
| 32 | ADR-14 | `tools/deps.json` mirrors s9.2 with the named `sim` public-type exception; CONTRACT-0 before lanes. | 06 A1, C2-04, C1-10 |
| 33 | s8.1 | Lite caps column; player-slot row; "visible entity mesh nodes" 800 / 200 / 200 with far pools; caps live in `match_rules.json`. | C1-01, C1-17 |
| 34 | s8.2 | iPhone 11 marked v1.1; web heap 256 MB -> 1 GB; web audio <= 15 MB; `ClientSession.tick` budget; atlas 256^2; chunk triangle wording; mobile draw budget note. | C1-20, C1-16, C1-23, C2-31, 03 amendment 3, 07 ART-A1 |
| 35 | s8.4 | Dedicated vCPU, 6 matches per host (4 on shared), spare rule, ~EUR 60/month; tick budget cites the re-baselined 03 s4.2 table and default profile. | C1-08, C1-22, C1-02 |
| 36 | s9.2 | `sim` lists `sim/orders`, `sim/control`, `sim/steer`, `AlertKind`, `LandingGrade`, `SimAiHook`, `CommandSinkBase`; `sim_ai` implements the hook; `net` may use `Assist` and read `Terrain`; `server` has `ProtocolValidator`/`MatchConfig`; `input` may reference `PilotInput`; `ui` may reference the named `sim` public types; `campaign` may reference `CommandSinkBase`; `app` holds `SettingsModel`, `match_controller.gd`, `offline_host.gd`. | C2-04, C2-12, C2-36, C2-23, 06 A1 |
| 37 | s9.3 | Offline client reads `LocalSimView` directly; optional worker thread on native. | C1-01 |
| 38 | s9.4 | `SimWorld.load_map(map, seed, rules)`, `remove_player`, `set_ai_hook`, `deserialize(bytes, content, hook)`; `Command.Kind` 0-15 incl. `SET_ADJUTANT`, `DEBUG_*`; `step_ship(s, input, def, common, rules, terrain, dt)`; `step_projectile(p, v, def, rules, dt)`; `Build.can_place`; `SimAiHook`; `SimEvent.Kind` 0-33; contract notes on `CommandSink.drive` and frozen enums; MODULE.md and R0 B supersede the listing. | C1-10, C2-03, C2-04, C2-12, 05 AR-1, 03 amendment 1 |
| 39 | s11 | Q5 answered (Crawler and Rail Lance stay); Q6 cut-ladder wording; Q10 Mac timing; Q13 queue and rating wording; new Q14 (odd counts), Q15 (portal SDKs), Q16 (SL-5 gate). | OWNER O-4; C1-14; C2-16, C3-15; OQ-R0-1, 06 A2, OQ-R0-6 |
| 40 | Appendix A | Execution order with S-FLIGHT-1 first after S-CI-1 and CONTRACT-0 gate; S-FLIGHT-1 scope and pass (tail-down landing, straight slugs, interpolation, novice criteria); S-SIM-1 real codec on production SKU; S-WORLD-1 mesher variants, boost path, Z8; S-NET-1 real browsers; S-NAV-1 amortised budget; S-WEB-1 heap and fast-start; new S-WEB-2; S-CI-1 slope criterion; S-IOS-1 v1.1 with Xcode and privacy manifest; S-BACKEND-1 5 days with restore drill. | C3-03, C3-02, C1-03, C1-07, C1-02, C1-08, C1-06, C1-09, C1-26, C1-05, C1-20, C1-21, C1-01, C1-11, C1-14, C1-12 |

Not changed on purpose: pillars P1-P5; the CF model's constant g = 6.0; the 30 Hz tick; the module list and layering direction of s9.2 (only named exceptions were added); the roster beyond the Silo; the three Doctrines; the fair-PvP rules of s3.4. Docs 02-08 are revised separately against R0 and this spine.

**Editorial sweep (2026-10-10, editor-in-chief, after 00-master-plan.md was written).** Wording fixes only; no decision changed.

| # | Section changed | Change | Authority |
|---|---|---|---|
| 41 | s5.1 item 1 | "For 1v1 the antipode is 171 s" restated: the antipode is unused; 1v1 is 90 degrees / 86 s. | OWNER O-5 |
| 42 | s5.6 | Resource template keyed to the 8 fixed slots (22.5 + 45 k) instead of the withdrawn `360/N * i` spacing (03 s2.2 forbids computing slots from N). | OWNER O-5, C1-09 |
| 43 | s6.3 | Orphaned Barge row moved back into the unit table; release label aligned with 08 I-01 (anchored v1.x, moving deck v2). | 08 I-01 |
| 44 | s9.1 | `docs/` line lists 00-10, `backlog/`, `reviews/`. | editorial |
| 45 | s10 | Core Exposure glossary entry notes per-mode timers. | C3-19 |
| 46 | s9.2 | `net` row: named `sim` types gain `SimEvent` and `CommandResult` (`EventRouter` and `ReplayWriter` consume `drain_events()`; the `COMMAND_RESULT` codec takes a `CommandResult`); `Build` stays unnamed (`Build.Reject` travels as an `int`). `tools/deps.json` edited in the NET-10 PR. | R0 B.9 A-27 (OWNER default approve) |
