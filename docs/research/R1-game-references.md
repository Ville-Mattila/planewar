# R1 - Game References and Lessons

| | |
|---|---|
| **Project** | Working title "Planewar" - moon-based 3D spaceship combat + RTS, Godot, mobile/PC/web |
| **Document** | R1 research: Triplane Turmoil and reference games |
| **Written** | 2026-10-09, for the owner and all planning/implementation agents |
| **Status** | Research input to the design docs. Not a design spec. |

**How to read this.** Section 1: Triplane Turmoil and the IP boundary. Section 2: 21 reference games with DO / AVOID lessons. Section 3: 20 design implications for downstream docs. Section 4: uncertainties and weak sources. Section 5: sources.

**Evidence convention.** Claims carry a source link. Text marked *(inference)* or *(proposal)* is my own reasoning, not something a source states. Many sources are secondary (Wikipedia, fan wikis, forums); Section 4 flags the weakest.

---

## 0. At-a-glance matrix

| Reference | Steal this | Skip this |
|---|---|---|
| Triplane Turmoil | Land-to-resupply loop; instant-kill bombs vs. variable gun damage; short, readable, high-stakes matches | WWI four-nation setting, name, any code or art |
| Planetary Annihilation | Server simulates, clients render; send only what each client can see; curve/keyframe state | Multi-planet scope; "constant zoom-out" UX; weak onboarding |
| Battlezone / BZ II | Command *through* the world you pilot in; wreck/pilot economy | Fiddly crosshair-menu command UI as the *only* command route |
| Savage / Natural Selection | Asymmetric roles; overhead commander view | Human-only commander dependency; no tutorial |
| Sacrifice | Direct, expressive unit control; gesture-style formations | Over-the-shoulder camera that hides the battlefield; no comeback |
| Carrier Command: Gaea Mission | Strategic layer + pilot one vehicle while others obey orders | Shipping with weak AI/pathfinding |
| Hostile Waters | Possess any unit; AI resumes when you leave | (Cryptic icon-order UI) |
| Brutal Legend | Troop cap; fly above to command | Console-grade controls, no minimap |
| Mindustry | Towers fed by supply; commandeer-a-unit; free, open, cross-platform | Sprawling belt logistics as core loop on phones |
| Rusted Warfare | Touch selection idioms; tolerance for lag; reconnect | Unverified netcode assumptions |
| Command & Conquer | Harvester > refinery > credits; power gating; adjacency build radius; sidebar queue | Original sidebar scrolling |
| Thrust / Gravitar / Lunar Lander | Gravity + inertia + fuel as the entire skill game | Unforgiving difficulty on day one |
| Sopwith / Luftrausers | Stall-as-tactic; loadout combinatorics; combo scoring | Single repetitive stage |
| Outer Wilds / Mario Galaxy / KSP | Head-up camera on spheres; accessibility over realism; floating-origin thinking | Fully free camera on a sphere without up-vector rules |

---

## 1. Triplane Turmoil

### 1.1 Facts

| Item | Detail | Source |
|---|---|---|
| Developer | Dodekaedron Software (Finland). Original authors: Markku Rankala, Teemu J. Takanen, Henrikki Merikallio; contributions from Risto Puhakka, Antti Lehtoranta, Mikko Kinnunen | [Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil), [Debian README](https://sources.debian.org/src/triplane/1.0.8-3/README) |
| Year / platform | 1996, MS-DOS, shareware. Later freeware (Home of the Underdogs says 1998) | [Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil), [HotU](https://homeoftheunderdogs.net/game.php?id=1623) |
| Genre / inspiration | Side-scrolling dogfighting shoot 'em up with single-player and local multiplayer; inspired by David Clark's 1984 *Sopwith* | [Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil) |
| Open source | Source, docs, images and sounds released under GPLv3 in 2009 (SourceForge, later GitHub). Stable port release 1.08 (Feb 2013) | [Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil) |
| Sequel | *Triplane Turmoil 2* (2006), Draconus Entertainment, Windows; 3D objects on 2D gameplay; six nations; 30+ multiplayer maps, some up to 36 players | [Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil) |

### 1.2 Mechanics in detail

**Controls and flight.** The player pitches nose up/down, rolls the aircraft 180 degrees, fires a machine gun and drops bombs; keyboard or joystick ([Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil)). The port's [manual page](https://manpages.org/triplane/6) adds the throttle model: hold the Power key to accelerate (or switch to toggle mode), release it to glide, and press Up+Down together for an air brake. The same page describes stalling as a very fast way to brake, but only for experienced pilots, and advises releasing power when turning with the Finnish plane. Roll (default key S) also doubles as the hangar enter/exit key.

**Altitude ceiling.** Flying too high thins the air and the pilot faints, sending the plane into a spiral; pressing up/down may slow the descent enough to recover ([Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil)). This is a diegetic *soft ceiling* - directly relevant to our "soft altitude ceiling at low orbit".

> Source gap: none of the pages I could reach describes gravity or stall in detail. Treat momentum, gravity-assisted dives and stall-turns as felt properties of the Sopwith lineage (see 2.5), not documented internals. A human should play the free port to confirm feel.

**Landing and resupply (the signature loop).** Each side has an airfield with a bomb-proof hangar, runway, small infantry garrison, turrets and tents. Planes land on their own runway to repair, refuel and reload ([Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil)). Per the [manual](https://manpages.org/triplane/6): release power, glide in, brake, stop on the runway, press the roll key and a mechanic pushes the plane into the hangar, where you set Bombs / Ammo / Fuel columns with Up/Down. Landing is widely described as the hard part ([Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil), [HotU](https://homeoftheunderdogs.net/game.php?id=1623)).

**Weapons and damage.**
- Machine gun: random damage per bullet; damage shows as smoke trails.
- Bombs: destroy an aircraft instantly; the main ground weapon and a crude air-to-air weapon. Optional kamikaze ramming ([Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil)).
- Bomb load matters: the manual says Finnish pilots need not conserve bombs because load does not affect that plane, and the Japanese plane runs short of fuel, especially with six bombs ([manual](https://manpages.org/triplane/6)). *(inference: load affects handling or fuel for the other nations)*

**Four nations, four trade-offs** ([manual](https://manpages.org/triplane/6)):

| Nation | Strength | Weakness |
|---|---|---|
| Germany | Balanced dogfighter | No standout stat |
| Finland | Fastest, toughest | Low bomb capacity, low turn rate |
| England | Never runs out of fuel/ammo | Low manoeuvrability, limited bombs |
| Japan | Largest bomb load, most agile unloaded, but fragile | Always short of fuel |

**Ground defences** ([Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil)):
- Infantry: weak anti-air, but about six together can threaten most aircraft.
- Flak: slow, high ceiling, accurate; direct hit ignites the plane; flying very low avoids it.
- Machine-gun turrets: lower ceiling, five-bullet bursts; one to four bursts can kill an inattentive pilot; fly above them.

Each layer has a different *counter-play altitude*, a cheap and readable way to give towers variety.

**Single player.** Each nation has a linear campaign (Wikipedia says six missions, [HotU](https://homeoftheunderdogs.net/game.php?id=1623) says five; sources conflict). The world situation shifts with earlier results; the player's side blunders diplomatically and the others unite against it, ending in a last-stand mission ([Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil)). Objectives are usually "bomb X" or "stop X being bombed"; some are recon. Reviewers describe a strict try-fail-retry rhythm: enemy bombers rarely miss, and losing one of your own buildings can fail a mission ([HotU](https://homeoftheunderdogs.net/game.php?id=1623)). Scoring comes mostly from planes shot down, plus ground installations and infantry. Pilots earn ranks from 2nd Lieutenant to Colonel and medals ([manual](https://manpages.org/triplane/6)).

**Multiplayer.** Up to four players on one computer (keyboard plus up to two joysticks), six maps, 2v2 alliances or free-for-all, with turrets and infantry optional. The goal is destroying the other players' bases while protecting your own. Options include unlimited ammo/fuel, a point target, and collisions where both planes die and each player loses a point. **There is no network play** ([Wikipedia](https://en.wikipedia.org/wiki/Triplane_Turmoil), [manual](https://manpages.org/triplane/6)). Download-site reviewers rate local multiplayer as the game's heart and solo as harder and more trial-and-error ([Acid-Play](https://acid-play.com/download/triplane-turmoil), [My Abandonware](https://www.myabandonware.com/game/triplane-turmoil-2dp)).

**AI.** Computer pilots can fill any empty seat. Reviews call the AI simple but deadly, bombers especially ([HotU](https://homeoftheunderdogs.net/game.php?id=1623)). A telling limitation: on the CAVERN map, computer-controlled English and Finnish planes are disabled because the AI cannot take off in caves ([manual](https://manpages.org/triplane/6)). Lesson: *AI that must perform the takeoff/landing ritual is a real engineering cost; budget for it.*

### 1.3 What made it fun and memorable *(analysis, not sourced)*

1. **One screen, whole map.** Every bomb run is a public, readable threat. Our globe cannot show everything, so the commander view and alerts must recreate "I can see the whole fight".
2. **Two kill speeds.** Random gun damage vs. instant-kill bombs makes every pass a risk calculation.
3. **The resupply ritual.** Sortie, return, rearm; landing is a skill test and a tense moment under fire.
4. **Asymmetric planes** give identity and counters with trivial stat tables.
5. **Chaotic local multiplayer** with base destruction as the win condition: short, loud, rematch-friendly.
6. **Cheap, deadly AI** that is easy to read, so mistakes feel fair.

### 1.4 Triplane Classic and the IP caution

- **What it is.** A community SDL port of the DOS game that aims to reproduce it exactly so high scores stay comparable. Build system: CMake; SDL2 and SDL2_mixer; Emscripten browser build documented ([suomipelit/triplane](https://github.com/suomipelit/triplane), [Debian README](https://sources.debian.org/src/triplane/1.0.8-3/README)).
- **Licence.** Dodekaedron Software Creations Oy, the copyright holder, licensed code, documentation, images and sounds in 2009 under **GPL v3 or later**. Port authors: Timo Juhani Lindfors, Teemu J. Takanen, Riku Saikkonen; SDL2/CMake work by the Suomipelit organisation ([Debian README](https://sources.debian.org/src/triplane/1.0.8-3/README), [GitHub](https://github.com/triplane-classic/triplane)).
- **Trademarks.** "Triplane Turmoil" is a trademark of Dodekaedron Software Creations Oy; "Triplane Turmoil 2" is Draconus Entertainment's. "Triplane Classic" is stated not to be a trademark, and the authors ask that substantially modified versions take a new name ([GitHub](https://github.com/triplane-classic/triplane)).

**Rules for this project** *(not legal advice; confirm with counsel before release)*:

1. **No code, assets, names or data tables** from Triplane Classic or any Triplane release. GPL-3.0-or-later is strong copyleft: embedding any of it would oblige us to license the combined work under GPL-compatible terms, which conflicts with a conventional closed commercial/app-store release.
2. **No clean-room contamination.** Implementation agents must not read or paste the Triplane source. If a human wants to study the feel, they should *play* the port and write behaviours down in their own words.
3. **No confusing names.** Avoid "Triplane", "Turmoil", "Classic", "Dodekaedron" and anything that echoes them in titles, store listings, package IDs or tags. Run a trademark clearance on our final name; "Planewar" is a working title only.
4. **Don't clone the fiction.** Four WWI-ish nations and their plane lineup are expression, not mechanics. Our factions, ships, towers, briefing text and UI must be original.
5. **Mechanics are fair game as inspiration** (land-to-resupply, bomb vs. gun, altitude ceiling, ground-defence variety) - general game ideas, implemented independently. Our space, RTS and base-building combination differs substantially from the original.

---

## 2. Reference games

### 2.1 Planetary Annihilation (Uber Entertainment, 2014; Titans 2015)

**What it is.** A spherical-planet RTS with procedural star systems, a metal/energy economy and a planet-smashing late game. Kickstarter 2012 (goal $900k, about $2.2M raised), launch 5 Sep 2014, Titans 18 Aug 2015; Metacritic 62 ([Wikipedia](https://en.wikipedia.org/wiki/Planetary_Annihilation)).

**Tech facts.**
- Client-server rather than lockstep. The server runs the multi-planet simulation at 10 ticks per second; clients render at up to 60 fps and mostly just draw what they can see. The server withholds updates for things a player cannot see, which doubles as anti-cheat ([ChronoCam article](https://www.forrestthewoods.com/blog/tech_of_planetary_annihilation_chrono_cam/)).
- All per-object state is stored as **curves** (linear, step and pulse keyframes). Idle units send nothing, velocity is derived client-side, and predicted end-keyframes are corrected when they change. Target: about 1 Mbit per player late in a game, up to 40 players ([same article](https://www.forrestthewoods.com/blog/tech_of_planetary_annihilation_chrono_cam/), [Q&A](https://www.forrestthewoods.com/blog/qa_planetary_annihilation_chrono_cam/)).
- Side effect: "ChronoCam" rewind, scrub and reverse. Costs: mispredicted keyframes waste bandwidth, particles are hard to reverse, and old replays break when the protocol changes.
- Terrain is built from Constructive Solid Geometry "brushes" ([Allen Chou](https://allenchou.net/2013/07/bending-solid-geometry-in-planetary-annihilation/)). I found no Uber primary source on pathfinding over spheres; secondhand accounts describe sectors with A* between them and a flow field inside each ([forum](https://forums.planetaryannihilation.com/posts/752550), [Habrador](https://blog.habrador.com/2017/07/why-you-need-to-learn-flow-field.html)). Unverified.

**What critics and players disliked.** A rushed, incomplete launch and technical problems (IGN 4.8/10). An Italian review described constant forced zooming out and poor surfacing of events (a satellite could die unnoticed); PC Gamer found fights across several small planets disorienting ([EveryEye](https://www.everyeye.it/articoli/recensione-planetary-annihilation-23760.html), [PC Gamer](https://www.pcgamer.com/uk/planetary-annihilation-titans-resurrects-a-flawed-rts-and-its-out-today)). Uber said orbital play felt empty and expanded it in Titans. Late-game performance was a recurring complaint; multi-threading arrived in 2016 ([GamingOnLinux](https://www.gamingonlinux.com/2016/11/planetary-annihilation-titans-massive-patch-released-with-multi-threading-goodness/page=1/)).

**DO**
1. Keep the simulation on a server; clients are thin renderers. It scales and resists cheating.
2. Interest-manage: send each player only what they can see.
3. Send predictive keyframes, not per-tick positions; ballistic motion under known gravity is cheap to predict *(inference)*.
4. Offer picture-in-picture so players can watch several fronts (praised by reviewers).

**AVOID**
1. A camera that forces constant zoom-out; use alerts and a globe overview.
2. Thin onboarding for a deep, novel genre mix.
3. Letting late-game unit counts outrun the weakest device; derive unit caps from the performance budget.
4. An "orbital" layer without real objectives, and multi-planet scope (one moon is plenty).

### 2.2 RTS + direct-control hybrids

| Game | How you command | How you take direct control | What units do when not controlled | Main complaint |
|---|---|---|---|---|
| Battlezone (1998) | Crosshair + command key opens unit menu with default order | You are always in a vehicle | Obey orders; friendly AI a little dicey | Unusual design, weak sales |
| Battlezone II (1999) | Same, plus F-key groups | Same | Same | Broken multiplayer at launch |
| Savage (2003) | One human commander, overhead RTS view | Everyone else plays FPS/melee | Up to 10 worker NPCs; field players get waypoints | No tutorial, steep curve |
| Natural Selection (2002) | Marine commander in chair, overhead view | Everyone else FPS | Players self-direct | Learning curve |
| Sacrifice (2000) | Wizard avatar summons and directs | Avatar-centric | Not documented in my sources | Camera, micromanagement |
| Carrier Command: Gaea Mission (2012) | Strategy map, orders, waypoints | Pilot one vehicle at a time | Other seven follow attack/move/follow orders | AI and pathfinding |
| Hostile Waters (2001) | Icon-based orders | Pilot any friendly unit | AI resumes command when you leave | Cryptic order UI |
| Brutal Legend (2009) | Follow/attack/defend; fly up to command | Hero avatar | Army follows orders | Console controls, no minimap |

**Battlezone (1998) and II (1999).** Base building, harvesting and production all happen from a first-person view. You aim at a unit and press the command key to open its menu with a default order preselected; pressing again at a target executes it. Scrap is the economy, gathered by scavengers and salvaged from wrecks; a destroyed vehicle's pilot ejects and can hijack another friendly vehicle ([Wikipedia](https://en.wikipedia.org/wiki/Battlezone_(1998_video_game)), [StrategyWiki](https://strategywiki.org/wiki/Battlezone_(1998))). The AI was reused from *Dark Reign*; the game undersold, with the producer blaming branding and the unusual design. BZII's multiplayer was broken until patch 1.1, and programmer Ken Miller blamed the genre mix: "FPS players don't want to think; RTS players don't want to die" ([Wikipedia](https://en.wikipedia.org/wiki/Battlezone_II:_Combat_Commander)).
- DO: let players order units without leaving the cockpit; make pilot ejection / re-embodiment a first-class event; make wrecks a resource.
- AVOID: crosshair-only command as the sole command route; fast action and slow planning with no way to zoom out or pause.

**Savage (S2 Games, 2003).** One commander per team plays an RTS; up to ten worker NPCs; field players receive waypoints and may ignore them; officers and buffs; no match without a commander ([Wikipedia](https://en.wikipedia.org/wiki/Savage:_The_Battle_for_Newerth)). Won the 2004 Seumas McNally Grand Prize, but critics noted glitches, no tutorial and a hard melee game; made freeware in 2006 ([GamesFirst](https://gamesfirst.com/articles/2003/savage-the-battle-for-newerth/)).
- DO: asymmetric roles and interdependence; players choose how much to follow orders.
- AVOID: requiring a human commander; shipping a hybrid with no tutorial.

**Natural Selection (2002 mod; NS2 2012).** The marine commander uses an overhead 2D view for upgrades, movement orders and supply drops ([Wikipedia](https://en.wikipedia.org/wiki/Natural_Selection_(video_game))).
- DO: supply drops are great "help the people on the ground" verbs; our commander can drop ammo or repair on the ship you are flying.
- AVOID: assuming both modes are equally satisfying; the series needed constant balancing.

**Sacrifice (Shiny, 2000).** A third-person wizard summons creatures with souls and mana instead of building production structures; formations are set by mouse gesture. Praised for creature design and spectacle; criticised for a camera that hid surroundings, heavy micromanagement, stalemates and armies that rarely recovered from early losses ([Wikipedia](https://en.wikipedia.org/wiki/Sacrifice_(video_game))).
- DO: gesture or drag formations beat menus.
- AVOID: snowball matches with no comeback; a camera that cannot see the battlefield.

**Carrier Command: Gaea Mission (Bohemia, 2012).** Capture islands on a 33-island moon; each is set to defence, resource or production and needs a supply line to the stockpile island. The carrier deploys up to four fliers and four amphibious tanks; you pilot one vehicle while the rest obey orders ([Wikipedia](https://en.wikipedia.org/wiki/Carrier_Command:_Gaea_Mission), [Expert Reviews](https://www.expertreviews.co.uk/?p=52204)). Metacritic 60. Critics said pathfinding undermined the premise: tanks stuck in ravines, overshot waypoints, fliers crashing into the carrier on repair-dock orders; patches 1.03-1.06 reworked AI and navigation ([PC Gamer](https://pcgamer.com/carrier-command-gaea-mission-review), [changelog](https://games.softpedia.com/progChangelog/Carrier-Command-Gaea-Mission-Patch-Changelog-120021.html)). The Xbox build's few buttons made commanding many units clunky ([CGMag](https://www.cgmagonline.com/review/carrier-command/)); no multiplayer.
- DO: supply-line-gated territory is an elegant economic rule.
- AVOID: half-finished AI order-following; fragile dock/repair orders (our return-to-base must be bulletproof); too few buttons for command.

**Brutal Legend (Double Fine, 2009).** "Stage Battles": merch booths on fan geysers are the resource; the hero orders squads and can fly up as a demon to command; multiplayer has a troop cap ([Wikipedia](https://en.wikipedia.org/wiki/Br%C3%BCtal_Legend)). Criticised for console targeting, no minimap and an RTS layer marketing never mentioned; about 215k US copies in October 2009.
- DO: a troop cap against runaway armies; command from above the fight.
- AVOID: hiding half the game in marketing; no minimap.

**Also worth stealing from.**
- *Hostile Waters: Antaeus Rising* (Rage, 2001): you can pilot any friendly unit and the game's AI resumes command when you step out; units carry AI "personalities" with different aggression; Metacritic 80. The closest ancestor of the owner's control concept ([Wikipedia](https://en.wikipedia.org/wiki/Hostile_Waters:_Antaeus_Rising), [MobyGames](https://www.mobygames.com/game/4925)).
- *Homeworld* (Relic, 1999): ball-shaped play volume, a Sensors Manager map, a camera that orbits a focused ship or group, a fleet that persists across 16 missions; Metacritic 93 ([Wikipedia](https://en.wikipedia.org/wiki/Homeworld), [GamesBeat](https://gamesbeat.com/after-20-years-get-ready-for-homeworld-3s-massive-sci-fi-fleet-battles/)).

### 2.3 Mobile RTS: Mindustry and Rusted Warfare

**Mindustry (Anuke, 2017-).** Top-down factory + tower defence + RTS where you pilot a small builder ship from a core. Windows, macOS, Linux, Android, iOS; free with no ads; GPLv3 Java; co-op and PvP servers, cross-platform; no web version mentioned ([Wikipedia](https://en.wikipedia.org/wiki/Mindustry), [GitHub](https://github.com/Anuken/Mindustry), [F-Droid](https://f-droid.org/packages/io.anuke.mindustry)). Reviewers found the logistics complex, with sprawling conveyor networks; Android Central found taps finicky and suggested tablets ([Android Central](https://androidcentral.com/mindustry-ultimate-sandbox-tower-defense-game-mobile-android-game-week)). Command mode is desktop-centric (Shift to select groups, Ctrl-click to commandeer one unit); v7 removed formations and command centres and players found the replacement sluggish ([Erekir alpha notes](https://planet.freegamedev.net/2022/07/16/build-136-erekir-alpha-release/), [Steam thread](https://steamcommunity.com/app/1127400/discussions/0/4631484492942497959)).
- DO: towers fed by a resource flow are addictive; saved layouts ("schematics") cut build tedium on touch; commandeering a single unit is our possession verb.
- AVOID: belt logistics as the core loop on phones; desktop modifier keys with no touch equivalent.

**Rusted Warfare (Corroding Games; Android 2011, iOS Dec 2020 per a Wikipedia snippet).** A 2D RTS built for phones. Touch idioms: two-finger drag to box-select or hold on a unit until a ring grows, minimap orders, control groups, rally points, strategic zoom; multiplayer supports reconnection, save/load and replays ([Droidgamers](https://www.droidgamers.com/news/new-rts-game-for-android-rusted-warfare-has-a-lot-of-potential/), [App Store](https://apps.apple.com/app/id1514329124)). The developer says even 1,000 ms latency is playable and refers to desync messages, which hints at a synchronised simulation, but no source confirms lockstep ([Steam thread](https://steamcommunity.com/app/647960/discussions/1/1694919808744455596)).
- DO: gesture-based selection (no modifiers), rally points, groups, reconnect and resume.
- AVOID: assuming desync-free play across phone, PC and browser; floating-point determinism is a hard target.

### 2.4 Command & Conquer (Westwood, 1995)

The series popularised the RTS with a Construction Yard (deployed from an MCV), power plants, harvest-and-refine economies and a persistent sidebar ([Wikipedia](https://en.wikipedia.org/wiki/Command_%26_Conquer_(video_game))). In Tiberian Dawn a Refinery needs a power plant and ships with a Harvester that carries about 700 Tiberium per trip; harvesters queue to unload; silos extend storage; damaged power plants output less and can take defences offline ([fan wiki](https://cnc.fandom.com/wiki/Power_plant_(Tiberian_Dawn))). New structures must sit adjacent to existing ones ([CNCNet](https://forums.cncnet.org/topic/6605-its-possible-change-the-timer-and-build-area/)). Each factory builds one item at a time from a queue that can be managed from anywhere. The 2020 Remastered sidebar added tabs and grew from eight to 18 build buttons to reduce scrolling ([CNCnz](https://cncnz.com/cc-remastered-update-sidebar-and-full-production/)).
- DO: a three-link economy (gatherer, depot, credits) plus power gating is easy to teach; adjacency-limited building creates frontiers and makes towers meaningful; production from anywhere decouples building from the camera.
- AVOID: endless sidebar scrolling on small screens; hard-coded rules (modders report much of Tiberian Dawn is hard-coded) - keep our balance in data files.

### 2.5 Thrust-physics and flight-feel games

- **Thrust** (Jeremy C. Smith, BBC Micro, 1986). Rotate, thrust, fire, shield and tractor beam under gravity with inertia. A hooked pod acts like a stiff rod, so ship and pod can whirl out of control; fuel limits you; wrecking a reactor starts a 10-second escape; later cycles reverse gravity or hide walls ([Wikipedia](https://en.wikipedia.org/wiki/Thrust_(video_game)), [Byte Cellar](https://bytecellar.com/?p=108)). DO: let gravity + inertia + fuel carry the skill ceiling and vary one rule per level. AVOID: a punishing first landing.
- **Gravitar** (Atari, 1982). Rotate-and-thrust with gravity toward the star in the overworld and downward in side-view levels; a tractor beam fetches fuel; first game with a real-time dynamic zoom into planets. Very hard and commercially weak (about 5,400 cabinets) ([Wikipedia mirror](https://www.wikipedia.org/wiki/Gravitar), [Arcade History](https://www.arcade-history.com/game/1006/)). DO: seamless zoom between orbital and surface scale, which is our commander-to-chase transition. AVOID: difficulty with no assists.
- **Lunar Lander** (Atari, 1979). Rotate, analog throttle, burn fuel, land softly on marked pads, zoom on approach; descends from Jim Storer's 1969 text game via DEC's graphical Moonlander ([Wikipedia](https://en.wikipedia.org/wiki/Lunar_Lander_(1979_video_game)), [Technologizer](https://www.technologizer.com/2009/07/19/lunar-lander)). DO: analog throttle and soft landing as a skill moment, thematically perfect on a moon. AVOID: pure realism; tune a learnable curve.
- **Sopwith** (David L. Clark, BMB Compuscience, 1984). Side-scrolling biplane bomber built to demo a networking system; takeoff needs speed or the plane stalls; loops and stalls dodge fire; destroy all buildings to finish; a novice mode removes stalling and gives unlimited ammo ([Wikipedia](https://en.wikipedia.org/wiki/Sopwith_(video_game)), [manpage](https://manpages.opensuse.org/Tumbleweed/sopwith/sopwith.6)). DO: assist modes instead of one difficulty. AVOID: stall rules that punish beginners without teaching.
- **Luftrausers** (Vlambeer, 2014). Pitch and thrust are separate and gravity replaces Asteroids' weightlessness; planes are built from weapon, body and engine parts (125 combinations); kills feed a combo meter that drives score ([Game Informer](https://www.gameinformer.com/games/luftrausers/b/ps3/archive/2013/08/31/asteroids-meets-sepia-drenched-wwii.aspx?amp), [Pocket Gamer](https://www.pocketgamer.com/articles/052369/r/)). PC Gamer found the single stage repetitive ([review](https://www.pcgamer.com/luftrausers-review/)). DO: modular hull/weapon/engine loadouts multiply content cheaply and suit data tables; a combo layer gives dogfights rhythm. AVOID: one environment forever; our moon needs biomes and base layouts.

### 2.6 Spherical gravity, camera and large-world lessons

- **Outer Wilds** (Mobius, 2019). Exaggerated Newtonian flight; planets orbit quickly with variable gravity; you counter momentum to slow; five miniature planets. Creative director Alex Beachum said the maths is not especially complicated but making it comfortable for players took many accommodations; over two million copies sold by August 2021 ([Wikipedia](https://en.wikipedia.org/wiki/Outer_Wilds), [VICE](https://vice.com/en/article/how-outer-wilds-developers-mobius-digital-made-space-physics-fun)). DO: honest physics plus assists; small readable planets make the horizon curve part of the fantasy. AVOID: drag-free Newtonian flight as the only mode, especially on mobile.
- **Super Mario Galaxy** (Nintendo, 2007). Spherical planets grew from a 2000 tech demo; director Koizumi said a sphere removes the wall that forces a conventional camera to turn around; reviewers generally praised the automatic camera ([Wikipedia](https://en.wikipedia.org/wiki/Super_Mario_Galaxy)). The team later said upside-down views reversed left and right and confused some players, so *Galaxy 2* kept Mario's head up wherever possible and added flat stages ([Iwata Asks](https://iwataasks.nintendo.com/interviews/wii/supermariogalaxy2/1/3)). DO: a head-up chase camera following the local surface normal, with controls relative to the camera or ship. AVOID: a camera that takes a full second to catch up after an abrupt gravity change; indie *Tiny Galaxy* shows the confusion and mild motion sickness ([review](https://nintendoworldreport.com/review/40908/tiny-galaxy-review)).
- **Kerbal Space Program.** Planet-scale flight needed a floating origin and, in KSP2, hierarchical positioning, because 32-bit floats lack precision; sphere-of-influence transitions are a recurring bug source ([KSP2 dev diary](https://kerbalspaceprogram.com/news/dev-diaries-developer-insights-10-collisions), [tracker](https://bugs.kerbalspaceprogram.com/issues/1043)). DO: choose a world scale where precision is a non-issue. AVOID: multiple gravity wells; one moon sidesteps SOI problems.
- **Godot's own numbers.** The [large-world-coordinates page](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html) recommends single precision up to roughly 2,048-4,096 units from the origin for first-person, 4,096-8,192 for third-person and 16,384-32,768 for top-down; beyond about 32,768-65,536 you usually need the `precision=double` engine build, which requires custom export templates, matching client and server builds, and may perform poorly on low-end mobile. Our planet sits at the origin with everything in a thin shell around it, so the maximum coordinate magnitude is roughly radius + ceiling (see item 10).

---

## 3. Design implications for our game

These are *proposals* for the design and architecture docs. Each names the reference that motivates it.

### Control and command

1. **One "possession" verb with a guaranteed return to automatic.** Any ship, tower or ground vehicle can be possessed with one input. On release (explicit, or when the player possesses something else) the unit returns to its last standing order, not to idle. Hostile Waters (AI resumes when you step out), Carrier Command (one piloted, others follow orders) and Mindustry (Ctrl-click commandeer) validate the idea. Model it as a per-entity state `AUTO | ORDERED | POSSESSED`.
2. **No avatar, so no game-over by death.** When a possessed ship dies, offer the nearest friendly unit (Battlezone pilot hijack, Hostile Waters chip swap). Only losing the HQ ends a match.
3. **The automatic layer is the product, not a feature.** Carrier Command and Battlezone were marked down mainly because uncontrolled units behaved badly. Budget real time for AI return-to-base, refuel/rearm landings, patrol, defend and harvest cycles, and make "return for resupply" the most heavily tested behaviour (Triplane's own AI could not take off in caves).
4. **Keep ground pathfinding small.** Combat is mostly free-flight ships plus static towers. Restrict ground movers to a few types (harvesters, crawlers) on a spherical grid with per-destination flow fields *(proposal)*; avoid PA-style navigation over full terrain.
5. **Two-way help between layers.** Following Natural Selection and Savage, commanders drop supplies, shields or repairs on the ship you are flying, and pilots ping targets back. Interdependence turns the RTS and action halves into one game.

### Camera and flight

6. **Three camera tiers with continuous transitions:** chase (possessed), tactical (low orbit, selection and orders) and commander (globe overview). Gravitar and Homeworld show seamless scale changes work; PA shows the cost when the overview needs constant effort. Add automatic alerts (base under attack, harvester lost) with tap-to-jump and a picture-in-picture "home" window.
7. **Head-up chase camera with damped roll.** Follow the local surface normal (Galaxy 2). On a sphere "up" changes continuously, so avoid abrupt flips and keep controls ship-relative so a lagging camera never changes what left means (Tiny Galaxy). Expert free-roll is optional.
8. **Arcade-Newtonian flight with assist tiers.** Thrust + gravity + inertia (Thrust, Gravitar, Luftrausers), a stabiliser that damps rotation and speed (Outer Wilds accommodations) and a novice mode (Sopwith). Replace Triplane's air mechanics with vacuum equivalents: a soft ceiling (thrust fades or "radiation" damage above altitude X) and retro-thrusters for the air brake. A quick "flip heading" move can carry Triplane's roll-180 identity *(proposal)*.
9. **Make the resupply landing the signature moment.** Pads and hangars, soft landing with analog throttle (Lunar Lander), fuel/ammo/bomb loadouts (Triplane). Auto-dock for novices, a score bonus for manual landings.

### World, economy and building

10. **Pick the planet radius from the precision budget.** Godot's guideline for third-person 3D is about 4,096-8,192 units from the origin. Aim for a radius of 4,000-6,000 plus about 1,500 units of ceiling (max magnitude 5,500-7,500) and treat 8,000 as an upper bound needing a spike. *Illustration (units arbitrary):* at R = 6,000 the circumference is about 37,700 units, so a 100 u/s fighter circles the moon in about 6.3 minutes, a tuning anchor for "much bigger than Triplane". Avoid the `precision=double` build (custom templates, mobile cost, web unknown).
11. **Economy: C&C's loop with a space skin.** Harvester ships, refinery, credits; power plants as soft gating (low power slows production and disables turrets); adjacency/radius-limited building around the HQ and outposts; a production sidebar usable from any camera. Keep all numbers in data files so Haiku and Sonnet agents can tune them.
12. **Towers draw from a supply network, not belts.** Mindustry proves towers fed by resource flow work, but belts sprawl. Use auto-supply inside a pylon radius with visibly drainable ammo/energy pools, and Triplane's altitude-based counter-play (flak weak at low altitude, MG turrets weak at high altitude) to differentiate tower types.
13. **Comeback and anti-snowball rules.** Sacrifice and Brutal Legend show snowball and stalemate risk. Use wreck salvage (Battlezone, Hostile Waters, Homeworld), a unit cap tied to power (Brutal Legend troop cap) and rotating objectives.
14. **Modular ships and towers from parts.** Luftrausers' hull/weapon/engine loadouts multiply content cheaply and suit data tables, which fits parallel agent work and the manufacturing mechanic.

### Multiplayer and technology

15. **Server-authoritative simulation with interest management and keyframes.** Copy PA's principles at 2-8 player scale: the server decides truth, clients see only what they may, and state arrives as predictive keyframes (position + velocity + timestamp), silent when units coast or idle. Possessed ships use client-side prediction and reconciliation; AI units use lower-rate interpolation. Plan lockstep out: action flight needs responsiveness, and cross-platform floating-point determinism is hard (Rusted Warfare's desync messages show the risk).
16. **Design the transport for the browser from day one.** Godot web export has no raw UDP or ENet, only WebSocket (client) and WebRTC; threaded export needs cross-origin isolation headers; browsers pause background tabs, which can drop networked games ([Godot docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)). Put networking behind an interface: ENet on native, WebRTC data channels (WebSocket fallback) on web, with robust reconnect and snapshot resync.
17. **Language and renderer follow web needs.** The same docs say web export uses the WebGL2 Compatibility renderer only, and that C# projects in Godot 4 cannot export to the web. If the browser is a real target, gameplay code should be GDScript (or native code/GDExtension where isolation headers are acceptable), even though a .NET SDK is installed. Flat-shaded low-poly art suits the Compatibility renderer. Re-verify against the Godot version chosen.
18. **Replays almost for free.** If state is already keyframes, store them for post-match replay and kill-cam. Do not promise live rewind (PA's costs: particles, protocol versioning).

### Onboarding, mobile and IP

19. **Teach in layers and state the hook in one sentence.** Savage, PA and Battlezone II lost players to genre confusion and missing tutorials; Brutal Legend lost them to marketing that hid half the game. Make the Story campaign the tutorial (flight, combat, landing, build, command, possession) and keep first sessions short. Mobile controls must be simple: auto-aim and auto-thrust options, large touch targets, one-finger or two-finger selection (Rusted Warfare), no desktop-only modifiers (Mindustry).
20. **Keep Triplane IP out entirely.** No code, assets, names or fiction (Section 1.4). Our moon, ships, factions and towers must be original.

---

## 4. Uncertainties and source-quality notes

- **Triplane specifics.** Gravity/stall internals, numeric stats and AI details are undocumented in reachable sources. Release year varies (1996 on Wikipedia; Home of the Underdogs lists 1998, likely the freeware date). Campaign length conflicts (five vs. six missions). One listing says no multiplayer; the manual and Wikipedia confirm up to four local players.
- **PA pathfinding** is secondhand (forum posts, a third-party blog). The ChronoCam article is a primary developer source from 2013; details may have changed.
- **Rusted Warfare.** Its Wikipedia page returned 404 on direct fetch, so release dates come from a search snippet. "Lockstep" is my inference from desync messages, replays and reconnect, not a developer statement.
- **Thin sources.** Mindustry touch design, Sacrifice idle AI and Battlezone's per-order behaviour were not documented in anything I could reach. Several reviews were truncated (IGN, Rock Paper Shotgun).
- **Godot docs** were fetched on 2026-10-09 (shown as 4.7); web-export limits and C# status may change by the time a version is chosen.
- **Legal.** IP and GPL notes are practical project rules, not legal advice.
- **Suggested spikes** *(proposal)*: a one-week flight-feel prototype with the assist tiers of item 8; a three-tier camera on a sphere; a precision test at R = 6,000 and 8,000; two clients over WebRTC.

---

## 5. Sources

**Triplane Turmoil / Triplane Classic**
- https://en.wikipedia.org/wiki/Triplane_Turmoil
- https://manpages.org/triplane/6
- https://sources.debian.org/src/triplane/1.0.8-3/README
- https://github.com/suomipelit/triplane
- https://github.com/triplane-classic/triplane
- https://homeoftheunderdogs.net/game.php?id=1623
- https://acid-play.com/download/triplane-turmoil
- https://www.myabandonware.com/game/triplane-turmoil-2dp

**Planetary Annihilation**
- https://en.wikipedia.org/wiki/Planetary_Annihilation
- https://www.forrestthewoods.com/blog/tech_of_planetary_annihilation_chrono_cam/
- https://www.forrestthewoods.com/blog/qa_planetary_annihilation_chrono_cam/
- https://allenchou.net/2013/07/bending-solid-geometry-in-planetary-annihilation/
- https://www.pcgamer.com/uk/planetary-annihilation-titans-resurrects-a-flawed-rts-and-its-out-today
- https://www.gamingonlinux.com/2016/11/planetary-annihilation-titans-massive-patch-released-with-multi-threading-goodness/page=1/
- https://www.everyeye.it/articoli/recensione-planetary-annihilation-23760.html
- https://forums.planetaryannihilation.com/posts/752550
- https://blog.habrador.com/2017/07/why-you-need-to-learn-flow-field.html
- https://wiki.palobby.com/wiki/Planetary_Annihilation_Titans
- https://vaporlens.app/app/386070/planetary_annihilation_titans/stats/details

**Hybrids**
- https://en.wikipedia.org/wiki/Battlezone_(1998_video_game)
- https://strategywiki.org/wiki/Battlezone_(1998)
- https://en.wikipedia.org/wiki/Battlezone_II:_Combat_Commander
- https://en.wikipedia.org/wiki/Savage:_The_Battle_for_Newerth
- https://gamesfirst.com/articles/2003/savage-the-battle-for-newerth/
- https://en.wikipedia.org/wiki/Natural_Selection_(video_game)
- https://en.wikipedia.org/wiki/Sacrifice_(video_game)
- https://www.witchboy.net/2001/01/
- https://en.wikipedia.org/wiki/Carrier_Command:_Gaea_Mission
- https://www.expertreviews.co.uk/?p=52204
- https://pcgamer.com/carrier-command-gaea-mission-review
- https://games.softpedia.com/progChangelog/Carrier-Command-Gaea-Mission-Patch-Changelog-120021.html
- https://www.cgmagonline.com/review/carrier-command/
- https://en.wikipedia.org/wiki/Br%C3%BCtal_Legend
- https://en.wikipedia.org/wiki/Hostile_Waters:_Antaeus_Rising
- https://www.mobygames.com/game/4925
- https://en.wikipedia.org/wiki/Homeworld
- https://gamesbeat.com/after-20-years-get-ready-for-homeworld-3s-massive-sci-fi-fleet-battles/

**Mobile RTS / economy**
- https://en.wikipedia.org/wiki/Mindustry
- https://github.com/Anuken/Mindustry
- https://f-droid.org/packages/io.anuke.mindustry
- https://androidcentral.com/mindustry-ultimate-sandbox-tower-defense-game-mobile-android-game-week
- https://planet.freegamedev.net/2022/07/16/build-136-erekir-alpha-release/
- https://steamcommunity.com/app/1127400/discussions/0/4631484492942497959
- https://en.wikipedia.org/wiki/Rusted_Warfare
- https://www.droidgamers.com/news/new-rts-game-for-android-rusted-warfare-has-a-lot-of-potential/
- https://apps.apple.com/app/id1514329124
- https://steamcommunity.com/app/647960/discussions/1/1694919808744455596
- https://en.wikipedia.org/wiki/Command_%26_Conquer_(video_game)
- https://cnc.fandom.com/wiki/Power_plant_(Tiberian_Dawn)
- https://forums.cncnet.org/topic/6605-its-possible-change-the-timer-and-build-area/
- https://cncnz.com/cc-remastered-update-sidebar-and-full-production/

**Flight feel**
- https://en.wikipedia.org/wiki/Thrust_(video_game)
- https://bytecellar.com/?p=108
- https://www.wikipedia.org/wiki/Gravitar
- https://www.arcade-history.com/game/1006/
- https://en.wikipedia.org/wiki/Lunar_Lander_(1979_video_game)
- https://www.technologizer.com/2009/07/19/lunar-lander
- https://en.wikipedia.org/wiki/Sopwith_(video_game)
- https://manpages.opensuse.org/Tumbleweed/sopwith/sopwith.6
- https://www.gameinformer.com/games/luftrausers/b/ps3/archive/2013/08/31/asteroids-meets-sepia-drenched-wwii.aspx?amp
- https://www.pocketgamer.com/articles/052369/r/
- https://www.engadget.com/tag/rauser
- https://www.pcgamer.com/luftrausers-review/

**Spherical gravity / camera / engine**
- https://en.wikipedia.org/wiki/Outer_Wilds
- https://vice.com/en/article/how-outer-wilds-developers-mobius-digital-made-space-physics-fun
- https://en.wikipedia.org/wiki/Super_Mario_Galaxy
- https://iwataasks.nintendo.com/interviews/wii/supermariogalaxy2/1/3
- https://nintendoworldreport.com/review/40908/tiny-galaxy-review
- https://kerbalspaceprogram.com/news/dev-diaries-developer-insights-10-collisions
- https://bugs.kerbalspaceprogram.com/issues/1043
- https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
