# C3 - Review: player experience, fun and scope

| | |
|---|---|
| **Reviewer lens** | Player experience, fun and scope (critic C3) |
| **Reviewed** | 01 (spine) and stage-2 drafts 02-08, Draft v0.1 |
| **Date** | 2026-10-09 |
| **Method** | Played four sessions in my head against the specs: (1) phone player, first 15 minutes; (2) PC dogfighter who never touches the RTS layer; (3) RTS player who never flies; (4) 4v4 team at minute 25. Then judged scope for a small team driving AI agents. |

Issue ids are `C3-nn`. Severity: blocker, major, minor. The structured list returned to the orchestrator carries the same ids.

---

## 1. Verdict in one page

The design is strong where it matters: one control path for humans and autopilots (05), readable autopilot state (mode tags, SL-3 chatter), a landing that is graded and scored, a Core-less player who stays in the fight, and an economy with a real second resource (Ice) that makes every sortie cost something. The documents are unusually well specified.

The plan is weak in five places that decide whether it is fun and whether it ships:

1. **The first minute and the first 15 minutes are inconsistent across docs.** 02 starts a player with no Shipyard; 05's bot books and 01 s0.4 assume one. 02's Mission 1 and 06's onboarding script are different missions.
2. **The signature moment (the landing) is not decided.** 05 reads 01 as a tail-down hover landing; 02, 06 and 07 did not adopt that reading, and the one spike that decides it (S-FLIGHT-1) sits late in 03's dependency chain.
3. **The moon is too big for 1v1 and 2v2 and about right for 8.** With bases 180 degrees apart a 1v1 raid is 171 s each way. 02's own sortie model (4 minutes) cannot be true there.
4. **Several phone-control and team-play details will hurt on day one**: stick and throttle on the same thumb, a commons economy that one teammate can drain or grief, no Core protection against a 4-Dart bomb rush.
5. **Scope is too wide for v1.** About 250 work seeds across 7 docs, 8 platforms, a full Nakama/FleetManager backend, 8 campaign missions, 6 new features from 08. A concrete cut list is in section 6.

---

## 2. Persona walk-throughs

### 2.1 Phone player, first 15 minutes (06 s12, 02 s16)

| Minute | What happens | Verdict |
|---|---|---|
| 0:00-1:00 | Web start gate, age prompt, language, cold open (06 s12). | Fine. Age screen before first flight is a drop-off risk; keep it one screen (as written). |
| 1:00-3:30 | Climb, rings, dive, boost. | **Boost and brake live on the throttle slider (06 s3.5), which is under the same thumb as the steering stick (06 s4.3: slider x 8-64, stick x 72-272).** The player cannot steer and boost at once. Rings that need "> 140 m/s" will frustrate. See C3-06. |
| 3:30-6:00 | Guns, bombs, rocket and flip. | Right thumb has FIRE, BOMB, FLIP, DOCK. Bombing by thumb on a moving target without any aim help is hard (aim assist covers guns only, 06 s3.6). See C3-23. |
| 6:00-8:00 | Fuel scripted to 22 percent, hold DOCK, auto-dock. | Good for touch. The landing is the star beat; it is passive for Full-assist players (about 20 s, 02 s11.2). Acceptable for the tutorial, a concern for the 30th sortie (section 3). |
| 8:00-10:00 | Release, pan, zoom, alert tap. | Good. This is the best beat of the script: it teaches the P1 idea in 90 s. |
| 10:00-13:30 | Build an Autocannon and Solar Array, queue a Harvester, possess the Autocannon. | Good, **but it contradicts 02's Mission 1**, which has no base, no enemies, no towers (C3-09). |
| 13:30-15:00 | Results, medals. | Fine. |

Two further phone problems: the Chase HUD already has about 20 elements in a 720 x 340 du safe rect, and 08 wants to add a wing button, a Mark REC button, a "Need supply" entry, an Almanac strip and a chatter feed (C3-21). In Commander view, opening the first Skirmish means 4 placements in the first 60 s from a drawer that is closed by default in COMPACT (06 s4.4) and a placement mode that dives the camera to 1,200 m (06 s7.3). That is workable only if the start kit already contains Shipyard and Vehicle Bay (C3-01).

### 2.2 PC dogfighter who never wants the RTS layer

- Skirmish and Campaign: fine, the Adjutant is on by default (01 s4.3).
- **Quick-match PvP: the Adjutant is off (01 s4.3, 02 s14). In 1v1 a pure flyer must still place Solar, Shipyard, Refinery, Outposts.** That contradicts P1 ("ignore the RTS layer entirely and just fly ... both are complete ways to play"). See C3-07.
- Campaign: M4 to M8 are RTS missions (power ratio, Reactors, Extractors, supply chains). Missions unlock in order (02 s16.2), so a dogfighter is gated by RTS content. See C3-10.
- The early game is good for this player: Dart airborne by 1:02, a first-sortie window of nearly two minutes with nothing else to do (02 s8.7).
- A 4-Dart bomb rush on a Core (8 bombs, 3,200 damage vs 3,000 HP) is the dogfighter's best weapon and also ends the match at about 3:00 (C3-05).

### 2.3 RTS player who never flies

- Commander view, a 18-tile drawer with no scrolling, last-command-wins, production from every camera: good, C&C-literate.
- Mission 1 forces a manual landing at grade B+ and Mission 3 forces possessing a Dart to kill a Bomber (02 s16.2). Both are required objectives. See C3-10.
- By design the autopilot is conservative: 12-18 percent hit rate, 60 m terrain margin, level bomb runs, defensive-only flip (02 s11.2). A human pilot is promised 1.4x damage per Ice. **An RTS-only player is therefore structurally weaker per Ice than a hybrid.** In 4v4 this is a role (commander plus pilots, Pilot/Commander score split). In 1v1 it is a skill gap with no stated viability target. See C3-20.
- Bombers sit docked until ordered (01 s4.3). A commander who wants a raid must order ATTACK or ESCORT per squad; the UI supports it (06 s7.2). That is fine, but it needs a tutorial beat; the current script has none.

### 2.4 4v4 team at minute 25

- Per 02 s8.9 a team holds about 92 ships and 30 Harvesters; with eight players about 180 ships are alive. The interest budget and caps handle it (01 s8.1), the player does not: alert feed 6 rows, ticker, chatter feed, Adjutant feed, toasts, hand-over requests all compete for a phone screen. See C3-21.
- **Team commons:** the stockpile and queues are shared and "any teammate may add to or cancel from any queue" (02 s6.4). Four strangers will drain the pool on the first minute and cancel each other's Bombers. See C3-08.
- Frontier vs interior roles (02 s8.8) are good design: interior players fund, frontier players fight. Make sure matchmaking tells interior players why they are quiet for 8 minutes (a one-line role hint in the loading screen).
- Match length: model median 22-26 min is a bot number. Humans can end a match in 3-4 min by rush or stall past 40 min. See C3-05 and C3-19.

---

## 3. Specific questions from the brief

### Is possession and release satisfying? Are autopilots trustworthy enough?

Yes on paper, and this is the best-thought-out area of the plan.
- One input to possess, one to release, a 0.5 s camera that hides the round trip, a safety handoff, and saved or pending orders (01 s4.4, 05 s2).
- Mode tags on every unit (05 s6.1) and SL-3 chatter make autopilot decisions visible. Carrier Command failed on exactly this (R1 s2.2).
- Trust numbers are testable: dock success >= 99 percent, crash <= 0.5 percent (BAL-15).
- Two cautions. (a) The release button is top-right, amber/red zone, on phones (06 s4.3). Release is the safety verb of the game; it should sit in a green or amber zone near the right thumb (swap places with PING). (b) Quick Fly (06 s7.6) lets a pilot jump into a serviced ship instead of landing, which is good flow but removes any reason to land manually (next question).

### Does the resupply landing stay fun on the 30th sortie?

Mostly, if three things are fixed.
- **Decision:** the landing model (tail-down hover vs level touchdown) is unresolved (C3-02). A tail-down hover landing on a pointer with no assist is a lunar-lander skill. It is fun once and a chore on sortie 30 unless it is fast.
- **Time on the pad:** a full service is 15 s, plus about 20 s of auto-dock approach on touch and gamepad. The Sortie Card (08 SL-1) fills the wait and is worth keeping. Add: the pilot may launch at any time (already in 02 s2.3).
- **Incentive:** the only rewards for landing yourself are a 10 percent repair-time bonus and score (01 s3.1.4, 02 s11.1 P-3). A skilled player's optimal play is: release at 25 percent fuel, let the autopilot land (99 percent), Quick Fly into a serviced ship. Landing then becomes a spectator event. SL-1 grades and banking give landing a reason; keep grades and the Sortie Card in v1 (section 7). Do not add Supply Canisters (SL-5): they let a pilot skip the landing, which undermines P2.

### Are matches likely to hit 20-30 minutes?

- With bots: probably, the model was built to hit it, and BAL-01 gates it.
- With humans: not reliably. Three failure modes: early Core rush (C3-05), turtling stalemate until the 30:00 and 40:00 rules (they only weaken shields and stop Ore regeneration, 02 s12.1; Core Exposure does not force fights), and 4v4 on a phone where a 40:00 hard end is a long session. Per-mode timers (C3-19) and a rush gate (C3-05) address this.

### Is the moon too small or too large for 2 vs 8?

| Players | Slots (01 s5.7) | Neighbour distance | Verdict |
|---|---|---|---|
| 8 (4v4) | 8 at 45 degrees | 4,712 m, 43 s | **Tight but right.** Contact by 1:45 (02 s8.8). Do not shrink R. |
| 4 (2v2) | 4 at 90 degrees | 9,425 m, 86 s | Acceptable. Sortie 3-4 min. |
| 2 (1v1) | 2 at 180 degrees | **18,850 m, 171 s one way** | **Too large.** A raid sortie is 6+ minutes round trip. 02 s8.5 assumes 4.0 min and BAL-16 allows 150-330 s. These cannot both hold. |

On the owner's question "is 6 km very large enough": for 8 players it is the right minimum, for 1v1 it is already too large. Making R bigger would hurt 1v1 and 2v2 unless speeds scale up, and raises the float32 risk (ADR-03). The fix for small player counts is slot spacing, not radius (C3-04). The extra surface still matters: poles, flanks and the far side stay empty in 1v1, which is where the Midnight Pole fight lives. Recommendation to the owner: keep R = 6,000 m; make 1v1 use slots 90 degrees apart.

### Is the campaign a good tutorial?

The structure is good (M1-M3 free chapter, M4 economy, M5-M8 expansion), but:
- 02 M1 and 06 s12 disagree on what Mission 1 is (C3-09).
- RTS arrives at M4. A player who chose the RTS fantasy plays 3 flight missions first.
- M4 has 9 objectives including a Hauler delivery and a Pylon chain (C3-10). Split it.
- M5 depends on the moving sun, M8 on the Rail Lance (a cut candidate). Both are on the v1 cut path (section 6).
- The finale is text and speaker blips only (07 s8.2); fine.

---

## 4. Rating of the 08 shortlist

Scale: Keep = in v1; Simplify = in v1 with a smaller scope; Defer = v1.x.

| Slot | Feature | Fun value | Cost to a small team | Verdict | Reason |
|---|---|---|---|---|---|
| SL-1 | Landing Grades, Sortie Card, banking | High. Gives the landing meaning, fills the 15 s dock wait. | Low | **Keep, simplify** | Keep grades, points, Sortie Card, stamp. Drop the unbanked-pool forfeit rules and `player_score` replication; add points straight to the Pilot score (C3-13). One grade system with 02. |
| SL-2 | Form on Me (2 wingmen) | High for phone and casual players: escorted bomber run with one button. | Low-medium | **Keep** | Pure client-built ESCORT commands on an existing order. Make it a context tap on the FIRE cluster, not a new button (C3-21). |
| SL-3 | Radio chatter, callsigns | High. Makes autopilots readable, the core of P1. | Low | **Keep** | Text only in v1. Share the feed with alerts (C3-21). |
| SL-4 | Taught Routes | High ceiling, niche audience. | **High**: new Route type in `core`, two new order kinds, 134-byte ORDER payload, server validation, ribbons, library, auto-naming. | **Defer to v1.x** | Needs a UI that a phone player will not find in the first 15 minutes, and the right thumb is full. Ship when v1 telemetry shows deck-flying demand. |
| SL-5 | Supply Canister | Medium. Fun for a commander, but a pilot can skip landing. | **Medium-high**: new projectile behaviour, new order, AI divert logic, tower priority, replication, and **ADR amendment A-1** that dilutes P2. | **Defer; reject A-1 for v1** | Landing is the signature moment. Take the alternate (I-09 Relay Combo) or nothing. |
| SL-6 | Meteor Fall / Moon Almanac | Medium-high: gives dead mid-game minutes a focus, and the symmetric seam fights help 1v1 pacing. | **Medium-high**: schedule in match-start state, saves and replay header; per-map meteor sets; neutral wrecks; bot objectives; VFX; changes the 02 salvage share (BAL-22). | **Defer to v1.x, first in line** | If 1v1 pacing is still dead after C3-04, bring it back first. |
| I-03 | Relay capture rules | n/a | Low | Keep | Already in 02 s5.3. |
| I-16 | Cruise assist (auto-throttle) | **Essential for touch.** | Low | **Keep, make default on for touch** | Fixes the stick-and-slider problem together with C3-06. 06 Q-UX-2 default off should flip. |
| I-24 | Earth Clock | Low-medium. | Very low | Keep | Presentation only. |
| I-04 | Moving-sun mechanics | Medium for one campaign mission. | Medium (lighting, solar, cold-trap rule) | Defer with M5 | See C3-14. |
| I-15 | Cosmetic rules | n/a | Low | Keep | Already in 02 s17.3. |

08 amendments: A-1 reject for v1. A-2 (crew stations), A-3 (Lifeboat) and A-4 (Barge, Mass Driver) are v1.x and must not enter any v1 seed list.

---

## 5. Issues

### C3-01 (blocker) Start kit: 02 contradicts 01 s0.4 and 05's bot books

**Problem.** 02 s8.1 starts a player with Core, Refinery and one Harvester; the Shipyard and Vehicle Bay are built in the first 30 s (400 + 300 Ore, 35 s and 30 s, with only 2 construction slots, 02 s8.7). 01 s0.4 ("You queue two Harvesters and a Dart, drop a Solar Array and an Autocannon") and 01 s3.3 ("Two Harvesters, Solar, first Dart") assume production exists at 0:00. 05 s7.3 opening books never build a Shipyard or Vehicle Bay (the Vanguard book starts with `produce harvester`), and 05's cross-doc list assumes a start kit of Core + Refinery + Shipyard + Vehicle Bay + 1 Harvester. Run against 02's defs, every Normal bot would fail its first step and BAL-02/BAL-03 could never pass. For a phone player it also means 4 placements in the first 60 s.

**Required fix.** 02 s8.1 `start_kit`: Core, Refinery (500 m toward Field A), **Shipyard** (adjacent to the Core, with its launch pad), **Vehicle Bay**, 1 Harvester already mining. Lower `start_ore` from 1,500 to 800 and keep `start_ice` 300 so the opening choice stays real (Solar, 2nd Harvester, Dart, Autocannon). Rewrite the 8.7 opening log (Dart #1 airborne about 0:28; first-sortie window 0:30-3:00), re-derive 8.8 and 8.9 with `tools/econ_model.py` (GD-21), and move the BAL-02 band to 0:25-1:30. 02 s6.1 footnote: tier 3 is open at 0:00. Per-player "pre-built" counts as `max_per_player` use. 05 s7.3 books stay as written.

### C3-02 (major) Landing model unresolved; it is the signature moment

**Problem.** 01 s3.1.4 says "pitch within 25 degrees of the pad normal" and allows 15 m/s horizontal speed at touchdown. 05 s5.5 reads this as a tail-down powered hover landing (Lunar Lander) and files it as an open question; the 02 landing grades (s17.1), 06's landing guide (s6.4, "pitch from pad normal") and 07's ship art do not say which model they assume. A 15 m/s horizontal allowance and the SL-1 "dead-stick" bonus point to a fly-in rolling landing; the 25 degree rule reads either way. This decides ship art (landing legs), the HUD guide, the onboarding (06 s12 "guided manual landing on a training pad") and how hard the tutorial's required landing is. A wrong guess here costs rework in 02, 05, 06 and 07.

**Required fix.** (1) 03 TA-30 / S-FLIGHT-1 must implement **both** landing models behind a tuning switch: A = tail-down hover (05 s5.5 as written), B = fly-in with a nose-up flare (touchdown with the body up-axis within 25 degrees of the pad normal and horizontal speed up to 15 m/s along the pad, with a short rolling stop, pad radius 12 m). Pass criterion added to 01 App. A S-FLIGHT-1: "three novice testers land within 10 minutes on model A or B; choose the model with the lower median attempts and fewer than 20 percent crashes; a Raw (mouse) tester lands in under 15 attempts." (2) Default until the spike reports: model B for ships whose `a_thrust` < 1.5 g, model A is kept only if it wins; 02 s2.2 `flight_common` gets `landing_model: "hover" | "fly_in"` so the choice is data. (3) 02 s17.1, 06 s6.4 and 07 s1.3 each add one sentence stating "landing model per S-FLIGHT-1 result" and reference the data flag. (4) 05 s5.5 phases L4-L6 get an alternate L4b for model B (already noted in 05).

### C3-03 (major) The spike that decides feel comes too late

**Problem.** 01 App. A says S-FLIGHT-1 blocks 02, 05 and 06. In 03, TA-30 (S-FLIGHT-1) depends on TA-12, **TA-23 (the planet renderer)** and TA-19 (build/economy/docking) and is not on the critical path (TA-04/05 -> TA-11/12/13 -> TA-18 -> TA-22 in parallel with TA-23 -> TA-25). The first test of whether flying on a sphere is fun would arrive after the sim core, the renderer and economy docking exist, and 02's anchors, 05's landing law and 06's touch layout are all written against guesses.

**Required fix.** 03 TA-30: `Depends on` = TA-04, TA-05, TA-12 only. The prototype runs on a flat-shaded icosphere with the Chase camera stub, no chunked LOD, no economy; docking uses a stub pad entity. Size 4 agent-days stays. Add TA-30 to the critical path right after TA-03 (CI) with the sentence "No downstream lane opens (05 steering, 06 touch layout, 07 ship art beyond the Dart, 04 beyond the codec spike) until TA-30 reports." Add an explicit first-playable milestone to the roadmap seeds: "Dart flying, shooting, bombing and landing on a sphere, keyboard and touch, week 3".

### C3-04 (major, against 01) 1v1 on the antipode is dead air

**Problem.** 01 s5.7 puts a 1v1 at slots 0 and 180: 171 s of flight one way (01 s5.2). 02 s8.5 assumes a 4.0 min typical Dart sortie, BAL-16 expects a median sortie of 150-330 s, and 02 s8.7 has the first contact at 2:30-5:00. With a 342 s round trip and a fight, a base raid sortie is 7+ minutes: out of band, and the player flies two minutes of nothing per leg. 2v2 (86 s) and 4v4 (43 s) are fine.

**Required fix (ADR amendment to 01 s5.7, owner decision; default shown).** Replace "2: 0/180" with "**2: slots 0 and 2 (90 degrees apart, 9,425 m, 86 s)**; the other six slots are unused and keep 50 percent yield (01 s5.6)". 4 players stay 0/90/180/270. Teams: contiguous blocks unchanged. 02 s9.1 adds `slots_by_player_count: {"2": [0,2], "4": [0,2,4,6], "8": [0..7]}`. 02 s8.7 timeline re-run (contested field distances stay; the poles stay 9,425 m from every base). Add BAL-32: "1v1 base-to-base Dart transit 80-100 s". Impact: `tools/moonbake` validation of unused slots, 03 TA-16 (map set), no ADR-03/04/05 change. If the owner declines, 02 s8.5 and BAL-16 must be rewritten for a 6+ minute 1v1 sortie and S-FLIGHT-1 must test a 171 s transit for fun.

### C3-05 (major) No protection against an early Core rush; human matches can end at 3 minutes

**Problem.** Core 3,000 HP (01 s3.1.3); bomb 400 vs structures; Dart carries 2 bombs (02 s2.3). Four Darts (600 Ore) deliver 8 bombs = 3,200 damage. Darts are airborne at 1:02 and the nearest 4v4 enemy base is 43 s away. A human team can kill a Core at about 3:00. The only counters are towers (Autocannon cannot hit above 400 m, so a High bomb run ignores it) and, from 02 s10.4, two Flak Batteries, which a 3:00 player rarely has. The Shield Projector needs a Reactor (late). BAL bands never test a human-style rush, so the soak (bot) will not catch it; 01 P5 wants 20-30 minute matches.

**Required fix.** 02 s5.1 `core`: add `integrated_shield` = charge 2,400, recharge 40/s after 5 s, no Ice cost, **active until `core_shield_until_s` 480 (8:00)**, absorbing bombs and rockets exactly as a Shield Projector (02 s5.2, same rules s4.3.6), no Reactor needed; it is removed by Core Exposure. Add to `match_rules.json`: `core_shield_until_s: 480`. Add scenario test C-13: "4 Darts, 8 bombs, vs a Core with no towers at 5:00: Core survives with at least 600 HP after the first pass" and metric BAL-31: "Core destroyed before 10:00 in 2 percent or fewer of bot matches (Hard and Brutal 1v1)". 06 shows the shield timer on the Core. If the owner objects to a Core-only shield, the alternative is Core `hp` x2 until 8:00 (data multiplier), which breaks 01's "3,000" number less visibly but gives the same effect.

### C3-06 (major) Touch layout puts stick and throttle on one thumb; right thumb overloaded

**Problem.** 06 s4.3: throttle slider (x 8-64) and joystick (x 72-272) are both bottom-left. Boost is the slider's top detent and brake the bottom detent (06 s3.5). The left thumb cannot steer and operate the slider at once, so boost and brake are unreachable in a turn, yet the tutorial requires boosting through a ring (06 s12, "ring at > 140 m/s"). The right thumb carries FIRE (hold), BOMB, FLIP and DOCK (hold); 08 adds wing and Mark. With the Full tier set to auto-level and auto-dock the plane can be flown, but the first fight will feel like fighting the controls. S-UX-1 would likely catch it, but only after 06's whole layout and 37 UX seeds are built around it.

**Required fix.** 06 s3.5 and s4.3: (1) Replace the slider with a **vertical thrust slider that is set-and-forget (sticky) plus two small buttons on the right cluster: BOOST (tap, 56 du) and BRAKE (hold, 56 du)**; move FLIP to a swipe-up on the stick zone with the thumb. (2) `auto_throttle` default **on** for Full tier (Q-UX-2 default becomes "on for touch"; slider sets a target speed fraction). (3) Move RELEASE from the top bar to the bottom-right cluster, amber zone, above DOCK (swap PING into the top bar). (4) Add a pass criterion to S-UX-1: "boost-and-steer through a ring pair within 20 s by 3 of 4 novices". (5) Keep one new contextual button on the right cluster at most: WING/SUPPLY/MARK are folded into a single long-press on FIRE or a radial menu (see C3-21).

### C3-07 (major, against 01) P1 promise vs "Adjutant off in PvP"

**Problem.** P1 (01 s1) says the player may ignore the RTS layer entirely or ignore flying entirely: "both are complete ways to play". 01 s4.3 and 02 s14 turn the Adjutant off in PvP quick-match and ranked. In 1v1 a pure flyer must run Solar, Harvesters, Refinery and Outposts by hand; in 4v4 teammates can cover. P1 is false exactly in the mode that matters most for dogfighters.

**Required fix.** 01 s4.3 / 02 s14 / 05 s8: add Adjutant profile **`adjutant_economy`** (Harvester count, Solar/Refinery/Silo-free power balance, replenishment, no towers, no Outposts, no production beyond Harvesters and replacements) allowed in `pvp_quick_1v1`, `pvp_quick_2v2`, custom, co-op and skirmish. Visible to the opponent in the lobby as a tag ("Auto economy") like the input-class notice. Off only in the visible-ladder ranked mode that arrives after launch (01 Q13). 04 matchmaking key `s_adjutant` is not added; the tag is informational and the Adjutant's reduced scope keeps the fight even. 05 s8 adds a soak check: a human-equivalent pilot-only team with `adjutant_economy` loses to a Normal Commander bot at least 40 percent of games (data to tune the profile).

### C3-08 (major) Shared economy has no guard against griefing or draining

**Problem.** 02 s6.4: "any teammate may add to or cancel from any queue"; one shared pool (01 Q3). With four randoms in 4v4 the first-minute pool of 6,000 Ore (02 s8.8) is spent by whoever clicks fastest; a teammate can cancel others' Bombers. No design for resolving it, no mute, no accountability beyond "who queued what" display.

**Required fix.** 02 s6.4: (1) `CANCEL_PRODUCE` and `CANCEL_BUILD` valid only for the player who queued the item, or for any teammate if the owner is disconnected, eliminated or a bot. (2) New economy field `early_share_lock_s` = 120: until 2:00 each player may spend at most `start_ore / team_size` of the team pool (the rest is reserved), so the commons cannot be drained before the opening. (3) Add a per-player "contribution" line to the post-match screen (Ore spent, Ore mined, Ice delivered). (4) Add BAL-33: "no single player spends more than 45 percent of a 4-player team's Ore in the first 5 minutes in bot-vs-bot SOAK-A". 06 s7.5 shows the lock as a greyed amount with reason.

### C3-09 (major) Mission 1 is two different missions

**Problem.** 02 s16.2 M1 "Landfall": Halcyon Mare, slot 0 only, no enemies, 6 survey gates, climb to the uplink fade, auto-dock, manual landing grade B+; no base, no towers, no building. 06 s12: a 15-minute script with 3 rings, guns on drones, bombs on a crawler, a rocket and flip, scripted low fuel and landing, release, Commander pan, **build an Autocannon and a Solar Array, queue a Harvester, possess the Autocannon against a two-Dart raid**, results. 06 says "Missions 2-3 (02) teach ice, Haulers, power, hand-over and a full small skirmish vs an Easy bot"; 02's M2 is combat and M3 is possession and orders. The 02 gate count (6) differs from the 06 ring count (3). 06 UX-36 and 02 GD-30 would build different things.

**Required fix.** Make 06 s12 the authority for beats and 02 s16.2 the authority for objectives, and split by time. M1 (about 9 min): 06 s12 rows 0:40-8:45 (climb, rings, dive/boost, guns, bombs, rocket/flip, fuel-scripted landing, release). M2 (about 10 min): 06 s12 rows 8:45-13:30 (pan/zoom, alerts, build Autocannon and Solar, queue Harvester, possess a tower) merged with 02's M2 combat. Update 02 s16.2: M1 objectives list = those beats; **the manual landing at B+ becomes optional**, the required objective is "dock (auto or manual)". Delete 06 s12's "Missions 2-3 teach ice, Haulers..." sentence and replace with the actual 02 missions. Gate count 6 -> 3 (ring count of 06). 02 GD-30 and 06 UX-36 get the same acceptance table.

### C3-10 (major) Campaign forces both play styles and M4 is overloaded

**Problem.** 02 s16.2: missions unlock in order, objectives are required. A dogfighter must complete M4 (Solar, Shipyard, Vehicle Bay, 4 Harvesters, power ratio, Pylon chain, Extractor, Hauler delivering 200 Ice, 2 towers, survive a raid, Adjutant disabled; 9 objectives in one mission), M5 (Outpost, Reactor, power ratio hold, 1,500 Ice stockpile) and later. An RTS player must fly gates (M1), kill drones by gun (M2) and possess a Dart to kill a Bomber (M3). M5 needs the moving sun; M8 uses the Rail Lance (a cut candidate); M6 uses Shatter Belt rilles.

**Required fix.** 02 s16.2: (1) Add a per-mission **"Commander assist" option on M4-M8: the Adjutant may run the objectives marked `economy`** (the objective counts as done if the Adjutant did it); and a **"Pilot assist" option on M3 and M6**: allied autopilot wingmen (08 SL-2 Form on Me) can be used for the kill objectives; medals are capped at silver when assists are used. (2) Split M4 into M4a "First Light" (Solar, Shipyard, 4 Harvesters, power ratio) and M4b "Ice Run" (Pylon chain, Extractor, Hauler delivery, 2 towers, raid); total missions stay 8 by merging M7 into M8 as a lead-in (Relay capture + hold 6 min becomes the first third of M8). (3) **v1 ships M1-M4b, M6, M8 (7 missions).** M5 (moving sun) moves to v1.x with the moving-sun rule (C3-14). (4) M8's Rail Lance is replaced by a second Flak ring and a Missile Tower cluster, and the optional objective "lose no Bomber to the Rail Lance" becomes "lose no Bomber to Flak".

### C3-11 (major) Three different v1 map sets

**Problem.** 02 s9.2: Halcyon Mare, Shatter Belt, Rimewater. 07 s9.4: Cradle, Anvil, Glassfield, with different characters (Glassfield is huge flat maria, Rimewater is highlands; Anvil is rugged, Shatter Belt is cratered), different mode assignments and different campaign mapping. 03 TA-16: "Three v1 map recipes (equinox_8, a 4-slot and a 2-slot map)". 02 GD-22 writes resource blocks for 02's names, 07 ART-xx bakes 07's names, 03 TA-16 bakes 03's. Campaign JSON references a map id that nobody agrees on.

**Required fix.** One set, owned by 07 for names and by 02 for resources: **Cradle = Halcyon Mare (balanced, ranked default), Anvil = Shatter Belt (craters and rilles), Glassfield is dropped and replaced by Rimewater (highland, ice-rich, leaner Ore)** renamed **"Highfall"** only if 07 wants a naming pass. All three maps are 8-slot maps; 1v1 and 2v2 use slot subsets (C3-04). 03 TA-16 becomes "three 8-slot recipes: cradle, anvil, rimewater" and the 4-slot/2-slot map idea is deleted. 02 s9.2 and s16.2 map ids: `cradle`, `anvil`, `rimewater`. 07 s9.4 table rows updated to the 02 characters; 07 keeps its biome rules and validation checks.

### C3-12 (major) The 08 shortlist is too big for v1 and A-1 undermines P2

**Problem.** Six new features plus five refinements for a first release, with SL-4 (new Route type, two orders, a 134-byte payload, ribbons and library), SL-5 (new projectile behaviour, new order, ADR-level amendment A-1) and SL-6 (match-start schedule, saves, replay header, neutral wrecks, per-map data, bot objectives) each costing 5-15 agent-days plus changes to 02, 04, 05, 06, 07. A-1 lets a pilot refuel in the air, which weakens the one rule that makes landing the signature moment (P2). The right thumb on phones has no room for them (C3-21).

**Required fix.** 08 s3 and s8: v1 = **SL-1 (simplified), SL-2, SL-3** plus refinements I-03, I-16, I-24 and I-15. **SL-4, SL-5 and SL-6 move to v1.x** in the order SL-6, SL-4, SL-5. A-1 is withdrawn for v1 (SL-5 stays v1.x and is re-evaluated against the landing telemetry). 08 s11 seed list: remove or mark `v1.x` every seed belonging to SL-4/5/6; strip the Route type from the `core` additions in 03's v1 plan; remove the 134-byte ORDER payload note from 04 s2.5 for v1 (keep 04's 64-byte ORDER layout).

### C3-13 (major) Two landing-grade systems

**Problem.** 02 s17.1 defines grades S/A/B by fixed thresholds (S <= 2 m/s vertical, <= 4 horizontal, <= 5 degrees; A <= 4/8/10; B <= 8/15/25), points 25/50/100, medals and the M1 objective "grade B+". 08 SL-1 defines ACE/CLEAN/FAIR/HARD/BENT by a weighted quality score q, with different points (50/30/15/5), banking multipliers, a `DOCKED` event with grade fields, and `TouchdownMetrics`. Both claim the same events; 02 GD-27 and 08's seeds would implement two systems.

**Required fix.** Adopt SL-1's `LandingGrade` (q formula, ACE/CLEAN/FAIR/HARD/BENT/CRASH/AUTO) as the single v1 system. 02 s17.1: delete the S/A/B table; points per grade = SL-1 s4.4 values; `landing_b/a/s` score events become `landing_fair/clean/ace`; `feather_touch` medal = "5 manual landings graded CLEAN or better"; M1 optional objective "ACE landing". **Drop SL-1 banking (unbanked pool, forfeit, multipliers)** from v1: points go straight to the Pilot score, which removes `player_score` replication and the hopping rules. Keep the Sortie Card, the grade stamp, `pad_radius_m` on pads and the `DOCKED` grade payload. 08 SL-1 data block: remove `banking`.

### C3-14 (major) v1 scope inside 02 is wider than it needs to be

**Problem.** The design carries several systems that cost a lot and pay little in the first release: Siege Crawler (ground combat class, artillery projectile, `ground_mult`, Crawler brain, path-grid combat), Rail Lance (reactor + sensor mast gating, rail projectile, tower brain), Storage Silo (a structure and a cap lever that BAL-18 expects to hardly matter), structure salvage pods (`ceil(value/120)` pods per structure, BAL-30), Foundry double-tow, FFA lobbies (extra team colours A11Y-01, extra victory rules OQ-10), the moving sun (lighting, solar timing, `cold_trap_sunlit_mult`). 01 already marks the first two as cut candidates (Q5) but campaign M8 and BAL-12/14 depend on them.

**Required fix.** 02 / 01 owner decision, defaults below:
- **Cut from v1:** `siege_crawler` (02 s3, s4.1 `siege_gun`, `siege_shell`, 10.1 row, 05 s6.7, 07 `gnd_siege_crawler`), `rail_lance` (02 s5.2, 4.1 `rail_gun`, `rail_slug`, 07 `str_rail_lance`), `storage_silo` (raise Core to 3,000 Ore / 800 Ice and Refinery to +1,500 / +500 instead), structure salvage pods (ship wrecks only, 02 s13.1), Foundry double tow (`tow_slots` stays 1; Foundry's Hauler instead gets `cargo_ice` x1.25), FFA in custom lobbies, the moving sun and mission M5.
- **Keep:** Dart, Lancer, Bomber, Scout, Hauler, Harvester; Core, Outpost, Pylon, Solar, Reactor, Refinery, Ice Extractor, Pad, Hangar, Shipyard, Vehicle Bay, Sensor Mast, Relay Station; Autocannon, Flak, Missile Tower, Shield Projector.
- Result: 5 ships, 1 ground unit, 13 structures, 4 towers/support. 02 s18 metrics BAL-12 (Rail Lance row), BAL-14 (Crawler and Rail rows), BAL-18 (storage) and BAL-30 (pods) are rewritten; 07 saves about 11 agent-hours of modelling; 05 saves a brain and an AttackRun variant.

### C3-15 (major) Backend and matchmaking scope for a launch with little population

**Problem.** 04 specifies Nakama with email, device, Apple, Google and Steam auth, parties, friends, leaderboards, OpenSkill ratings per queue, a matchmaker with property bands widening at 30/60/90 s, an input-class split plus an "any input" pool, FleetManager with a process pool, a moderation queue, a deletion cascade, receipt validation, groups later. With 3 input classes x 4 queues x skill bands, a launch population matches almost nobody; the design already says bots fill after 60-120 s (02 s14). The effort (04 has 38 seeds) is mostly spent on features whose value appears only at population. Also 02 s14 offers quick-match for 1v1 and 2v2 only; 04 s10.4 adds a pooled `pvp_team` quick queue.

**Required fix.** 04 s10: **v1.0 online = quick match 1v1 and 2v2 (bot fill at 60 s), custom lobbies (private code, up to 4v4) and online co-op.** Matchmaking keys = region, mode, input class, content hash only; **no rating bands, no widening logic; ratings are recorded (OpenSkill update on `match_result`) but not used for matching until the first season patch.** Remove `pvp_team` quick queue. Leaderboards, seasons, groups and "any input" pool move to v1.x. Auth providers v1: device (guest), email, Steam on the Steam build; **Google and Apple sign-in are deferred together** (Apple requires Sign in with Apple when Google is offered; this keeps iOS review out of the v1 critical path). Keep: account deletion cascade, age band, team chat, report/block, receipt validation (Q2). Mark NET-xx seeds covering the removed pieces as v1.x.

### C3-16 (major) Launch platform matrix is wider than a small team can verify

**Problem.** The plan treats Windows, macOS, Linux, Android, iOS, web, Steam Deck, Steam, itch, Poki and CrazyGames as v1 targets, each with its own CI, export, store compliance, input and QA. iOS needs a Mac runner, notarisation or signing, TestFlight and Sign in with Apple (S-IOS-1); portals need SDK adapters with an unresolved ad-SDK amendment (06 A2) and Poki blocks external requests by default (06 Q-UX-7).

**Required fix (owner decision, default shown).** ADR-12 / 06 s9 / roadmap: **v1.0 ships Windows (Steam, covering Steam Deck), Android and web (itch.io and own site).** v1.1: iOS, macOS, Linux native, Poki and CrazyGames adapters (after amendment 06-A2 is decided). CI keeps the exports building for the deferred platforms from the start (cheap), but QA and store work wait. 06 UX-32 (portal adapters), 06 UX-33 iOS parts and S-IOS-1 (01 App. A) move to v1.1. This keeps "mobile and PC first-class" (Android + Windows/Deck at v1.0) and "browser easily adapted".

### C3-17 (major) Towing and tether physics have no owner

**Problem.** 01 s3.2: Haulers tow wrecks "with a tractor tether (a Thrust homage: the load swings on the tether)". 02 gives only `tow_slots` and a slower loaded cruise; 03 has a `TETHERED` flag bit and no tether model; 05 s6.5 says "Tether swing (01 s3.2) is the sim's" and adds a damping term. A swinging load is a coupled-body simulation on the server with network replication of the wreck, collision, and an autopilot that must stay stable while towing. Nobody has numbers.

**Required fix.** 02 s2.3 / s13: define the tether as a **kinematic rigid link**: the wreck is attached at `tether_len_m` = 25 m behind and 8 m below the Hauler's tail, follows by a critically damped spring on position (time constant 0.4 s), no pendulum in the sim, no collision for the wreck while towed, Hauler speed penalty as already specified. Swing is a presentation-only effect (07 vfx `tether_sway`). 03 s3 adds the one field `tether_target` to the side tables. 05 s6.5 deletes the damping rule (cap turn rates while towing instead, a data field). 02 GD-19 acceptance: "a towed wreck stays within 10 m of the attach point at 1 g turn".

### C3-18 (major) Bot-tier numbers disagree between 02 and 05

**Problem.** 02 s15 promises Normal: think 1 s, reaction +2 s, 40 commands/min; Easy 3 s / +6 s / 20; Hard 1 s / +0.5 s / 80; Brutal 1 s / 0 / 150. 05 s7.8 implements Normal 60 ticks (2 s) / 4 s / 30 per minute; Easy 90 ticks / 8 s / 15; Hard 30 ticks / 2 s / 60; Brutal 30 ticks / 0.5 s / 120. 02 says "05 implements these promises and each is a soak assertion"; BAL-27 win-rate bands will be calibrated to whichever set is built.

**Required fix.** 05 s7.8 is authoritative for cadence, reaction and command caps (it is the code). 02 s15: delete the rows "Command-rate cap" and "Think cadence / reaction delay" (they become a reference to `bot_profiles.json`), keep the behavioural promises (first Dart, first Outpost, first attack, raid targets, bombers from, shields, poles) and the win-rate ladder. Keep 02's player-facing numbers for command rates in the difficulty selection screen text only, generated from `bot_profiles.json` by 06.

### C3-19 (minor) Match-length levers are global, not per mode

**Problem.** Core Exposure at 30:00 and hard end at 40:00 are in `match_rules.json` for all modes (02 s12.1). 40 minutes is long for a phone session; 1v1 saturates its economy earlier than 4v4 (02 s8.9). Exposure only halves shields and stops regeneration; it does not force action.

**Required fix.** 02 s12.1 / s14: `core_exposure_s` and `hard_end_s` become per-mode data: `pvp_quick_1v1` 1,200 / 1,800; `pvp_quick_2v2` 1,500 / 2,100; `custom`/`coop` 1,800 / 2,400; `skirmish`/`campaign` per mission. Core Exposure additionally sets `core_bomb_mult` 1.25 (Cores take 125 percent bomb damage) so a siege after Exposure finishes in one more pass. BAL-01 and BAL-08 are evaluated per mode.

### C3-20 (minor) No viability target for a commander-only player

**Problem.** 02 s11.2 promises a pilot wins >= 70 percent of duels against an autopilot and >= 1.4x damage per Ice. P1 also promises that commanding without flying is complete. Nothing states what a commander-only player should achieve.

**Required fix.** 02 s18.4 adds: "a player who finishes M4 and never possesses wins >= 50 percent against Easy and >= 25 percent against Normal in skirmish; commander-only 4v4 teammate contributes >= 70 percent of the Ore-income share of a hybrid teammate". SOAK-F gains a `commander_only` flag (no possession after 0:00) and BAL-34 "a Normal Commander bot with autopilots only beats Easy at least 90 percent". Failing these means retuning orders (escort, attack-via defaults) rather than pilot stats.

### C3-21 (minor) Too many text channels and thumb buttons

**Problem.** Chase HUD on a 720 x 340 du phone: top bar, ticker, PiP, prompt, speed/altitude blocks, reticle with threat arrows, consumables, landing guide (06 s4.3). 08 adds the chatter feed (bottom-left, above the ping wheel), a wing icon above FIRE, Mark REC, "Need supply", Almanac strip and toasts; 05 adds an Adjutant feed and mode tags.

**Required fix.** 06 s6.1 / s7.4: **one feed** with priority lanes (P0 banner, alerts, chatter, Adjutant) and a filter button, 3 rows in COMPACT; the SL-3 `ChatterDirector` writes to this feed instead of its own. SL-2 wing is a long-press on FIRE (radial: Form, Attack, Break, Release), not a dedicated button. 06 UI lint (UX-37) adds "no more than 7 touch controls on the right half of Chase".

### C3-22 (minor) Autopilot bombing policy contradicts itself

**Problem.** 02 s11.2: autopilot bombing is a "level release from the Low band at a standard speed (what tower AI expects)". 02 s10.3 calls the Low band 150-400 m the crossfire of every tower, "nobody by choice"; 05 s6.3 picks Deck, High or Low per target cell by threat. The human advantage row is built on a policy the code does not have.

**Required fix.** 02 s11.2 Bombing row: "Autopilot picks a band by the target cell's defence (Deck vs Flak/Missile, High vs Autocannon only, Low otherwise), releases level at a standard speed and heading, makes at most 3 passes; a human can dive-bomb, toss from the Deck, hit a docking pad". Remove "Low band" wording. Keep the 1.4x telemetry target but allow a 1.2x pass band until S-FLIGHT-1.

### C3-23 (minor) Touch players have no bombing assist

**Problem.** Bombs are the main anti-structure weapon (BAL-14: bombs 40-65 percent of structure damage). 06 s3.6 aim assist covers guns only ("never touches thrust or fire"). Phone players will mostly bomb by order, and miss by hand.

**Required fix.** 06 s3.6 add assist **"Bomb release"** (FULL only, pointer never): while BOMB is held, the release fires on the first tick the predicted impact point (s6.3) is within 15 m of an enemy structure footprint or ground unit; no effect on steering or timing otherwise. P-4 counts it as an assist (reads world state), so it is locked per tier in ranked. Add `bomb_release_assist` to `defs/assists.json`.

### C3-24 (minor) The landing loop needs an explicit "sortie 30" design check

**Problem.** The loop (sortie 3-4 min, auto-dock about 20 s, service 15 s) is plausible, but nothing measures whether the pad time feels dead, and Quick Fly bypasses landing.

**Required fix.** 06 s13 / 02 s18.4 add playtest telemetry "median pad time per sortie (approach + service)" with a target <= 30 s on touch and <= 40 s on pointer, and a fun probe at sortie 10 and 30 ("would you skip landing?"). If it fails: allow launching with partial service from the Sortie Card (already possible), cut the auto-dock approach to a 120 m assist radius, or reduce `repair_time_s` by 20 percent (data only).

---

## 6. v1 cut list and must-keep list

### 6.1 Cut from v1 (or defer to v1.x)

| # | Item | Where | Saves | Condition |
|---|---|---|---|---|
| 1 | Siege Crawler and its weapon, projectile, brain, art | 02 s3-4, 05 s6.7, 07 | ground combat class, artillery path | Already a candidate (01 Q5). |
| 2 | Rail Lance | 02 s5.2, 07, 05 tower brain | Reactor + Sensor Mast gating, rail projectile | Replace in M8. |
| 3 | Storage Silo | 02 s5.1 | one structure, one cap lever | Raise Core/Refinery caps. |
| 4 | Structure salvage pods; Foundry double-tow | 02 s13.1, s7 | pod entities, BAL-30 | Ship wrecks only. |
| 5 | Moving sun and Mission M5 | 02 s16, 01 s5.5 | lighting, solar timing, one mission | Mission total 7. |
| 6 | Mission M7 merged into M8; M4 split | 02 s16 | one mission of content and test | C3-10. |
| 7 | FFA lobbies | 02 s14, 06 A11Y-01 | 4 extra team colours and rules | v1.x. |
| 8 | SL-4 Taught Routes, SL-5 Supply Canister, SL-6 Meteor Fall; amendment A-1 | 08 | about 15-30 agent-days across 6 docs | C3-12. |
| 9 | SL-1 banking pool | 08 | replication, forfeit rules | Keep grades and Sortie Card. |
| 10 | Rating bands, widening, "any input" pool, leaderboards, seasons, groups, `pvp_team` quick queue | 04 s10 | matchmaker logic and state | Ratings recorded, not used. |
| 11 | Google and Apple sign-in | 04 s10.2 | Sign in with Apple review path | Device, email, Steam. |
| 12 | iOS, macOS, Linux native, Poki and CrazyGames adapters | ADR-12, 06 s9 | store and QA load | v1.1. |
| 13 | WebRTC transport; DTLS evaluation (NET-33/34) | 04 | already v1.1 | Keep deferred. |
| 14 | Replays: scrubbing, kill-cam, caster tools | 04 s13, 08 | player-facing replay UI | Keep the recorder (needed for review). |
| 15 | Jolt debris and quality-tier extras | 03 | | Not in v1. |

### 6.2 Must keep (the game dies without these)

1. CF flight on a sphere with a Chase camera that never flips (S-FLIGHT-1, S-UX-2).
2. Possess and release as one input each, with the safety handoff, saved and pending orders, mode tags.
3. Two kill speeds (random gun damage, instant-kill bombs) and the altitude counters (Autocannon vs High, Flak vs Deck, Missile vs flip).
4. The graded landing with auto-dock as a touch assist, and the Sortie Card.
5. The Ore/Ice/Power economy with the pre-built start kit (C3-01) and the Ice-bleed per sortie.
6. Team-shared stockpile with owner-only cancel (C3-08), construction slots, Outpost presence rule (AR-1).
7. Autopilots that are boring and never stupid: Harvester, Hauler, Dart, Bomber, towers.
8. Commander bot Normal and Easy first; Hard and Brutal are tuning, not new code.
9. Short matches: Core shield until 8:00, per-mode Exposure and hard end (C3-05, C3-19).
10. Night readability and colour-blind-safe team shapes (P4).
11. Android + Windows + web with the same Compatibility renderer.
12. Campaign M1-M4 as the tutorial, with assist options (C3-09, C3-10).
13. Account deletion, age band, team chat with report and block (store gates).

---

## 7. Suggested first playable milestone (informational)

To protect the fun before the infrastructure: after CI is green (TA-01..03), build only `core/sphere`, `Kinematics.step_ship`, a flat-shaded icosphere, the Chase camera stub, keyboard and touch input, a gun, a bomb and one pad. Run S-FLIGHT-1 with both landing models. Nothing in 04 (beyond the codec spike), 05 steering, 06 touch layout or 07 ship art beyond the Dart starts before the report arrives. That is about three weeks of agent time and removes the largest single source of rework in this plan.
