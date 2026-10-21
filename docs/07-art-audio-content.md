# 07 - Art, Audio and Content Pipeline

| | |
|---|---|
| **Project** | Codename **PLANEWAR** - arcade spaceship combat + base-building RTS on a spherical moon. Godot 4.7.2. |
| **Document** | 07 - Art bible, audio design, asset/content pipeline, map recipe guide. Owner: Art & Audio Director agent. |
| **Status** | v1.0 (stage 3, revised 2026-10-10) |
| **Date** | 2026-10-10 (stage 2 draft: 2026-10-09) |
| **Inputs** | `01-vision-and-core-decisions.md` (binding, v1.1; Sections 3.1, 5, 6, 7 ADR-02/03/04/09, 8.2, 9, 12 "07"), `reviews/R0-resolution-register.md` (binding; canonical tables of Part B), `research/R1`, `R2` (s2.2, s3.3, s8, s13), `R3` (s4, s6.4, s6.7, s7). |
| **Ran during writing** | A Python prototype of the colour-vision-deficiency (CVD) check in Section 2.3. Nothing else was executed; Blender was not reachable, so exporter option names are marked "verify by introspection" (Section 4.6). |

**Decisions inherited from 01 (not re-opened here)**

1. One renderer everywhere: **Compatibility** (ADR-02). No glow/SSAO/SDFGI/volumetrics, LDR colour, 24-bit non-reverse-Z depth, one sun, sun-only shadows (off on low mobile), at most 8 local lights per mesh, no Decal nodes in 4.7, GPU particles without trails, pre-warm every material and effect on the loading screen.
2. Flat-shaded low-poly, strong emissive team colours on a grey moon (O9). Dart is 12 m long and is the scale reference (Section 3.1.1 of 01).
3. Triangle budgets (01 s8.2): Dart <= 600; Lancer/Hauler <= 900; Bomber <= 1,200; small structures <= 800; Shipyard/Refinery <= 1,500; Core <= 3,000; one shared palette atlas (ceiling 2,048^2); terrain chunk 2,048 tris; <= 2,000 live particle quads on mobile.
4. Terrain gameplay height is the baked u16 face; all visual detail is shader-only and has no gameplay meaning (ADR-04). Relief -500..+700 m (s5.2). R = `PLANET_RADIUS` = 6,000 m (owner-confirmed; map recipes carry `radius_m` 6000, everything else here is in metres or degrees).
5. Sun on +Z by default, terminator = equator, night lit by earthshine (s5.5). The moving sun (campaign missions and custom lobbies, stays in v1) rotates the sun direction through the global shader uniform `sun_dir` (Section 1.5). Cold Traps, Solar Plateau, maria, craters, rilles and poles per s5.4-5.6.
6. All content is JSON defs with a `presentation` key (mesh, VFX ids, audio ids) (ADR-09). `presentation` is stripped before the content hash and `sfx.json` / `vfx_prewarm.json` are excluded from it (Section 10). Repository layout of s9: `godot/assets/`, `godot/content/maps/`, `tools/blender/`, `tools/moonbake/`.
7. Web: 20 MB initial download, map packs 4 MB, single-thread, Sample audio mode (R2 s3.3). Mobile: draw calls <= 400, triangles <= 400 k (s8.2).
8. Clean-room IP rule: no Triplane code, assets, names, fiction (R1 s1.4, R3 s6.7). Compliance: colour-blind-safe team colours with shape cues (R3 s7.16).
9. Names in s6 and s10 of 01 stand; **07 renames nothing in v1**. Asset ids are derived from def ids, so any later rename is a find/replace in `content/`, `docs/` and `locale/` (Section 10).

---

## 1. Art bible

### 1.1 The look in six rules

1. **Saturation is reserved.** In the world, only three things carry chroma above about 25: team colours (units, structures), resource language (Ore ochre, Ice blue, Power pale yellow) and VFX. Hulls, terrain and props are near-neutral. This is what makes "where is the fight, whose is it" readable at a glance (pillar P4).
2. **Every face is one flat colour.** No textures other than the palette atlas, no normal maps, no baked lighting, no vertex colours. Colour comes from a swatch (Section 4.3), shading from the light model (Section 1.5).
3. **Silhouette first.** Each class has a unique planform (Section 1.3). A unit must be identifiable as a 48 px black-on-white silhouette.
4. **Team colour is light, not paint.** Team zones are *unlit emissive*, so the rendered pixel equals the verified hex in Section 2.2 in every lighting state, including night.
5. **No gradients, no glow.** LDR Compatibility has no HDR bloom. "Glow" is a flat additive halo quad. Facets, not smoothing, give form.
6. **One moon, one grey.** Cool grey moon, warm white sun, blue earthshine. The only warm hue in the sky is the sun.

### 1.2 Scale chart (Dart = 12 m reference)

Ship axes: length along nose-to-tail, span across wings, height. Structure footprints are in metres; `footprint_cells = ceil(footprint_m / 8.68)` (8.68 m = the smallest build-cell edge, at face corners; cells grow toward face centres, 01 ADR-05), so a mesh never overhangs its cells anywhere on the sphere. 02 owns the final `footprint_cells` (Rail Lance 4 x 5, hence its 31 x 39 m footprint below).

| Asset | Length x span x height (m) | Notes |
|---|---|---|
| Scout | 8 x 6 x 2.2 | smallest ship |
| **Dart** | **12 x 9 x 3.0** | reference |
| Lancer | 16 x 12 x 4 | |
| Hauler | 20 x 14 x 7 | tether hook underneath |
| Bomber | 24 x 20 x 6 | biggest ship |
| Harvester | 9 x 6 x 4 | ground, 6 wheels |
| Siege Crawler | 14 x 8 x 6 | ground |
| Pylon | 4 x 4 x 30 | tall, thin |
| Pad / Hangar | 26 x 26 x 0.8 / 26 x 26 x 9 | Dart span 9 m fits with 8 m margin each side |
| Autocannon / Flak / Missile / Shield / Rail | 13 x 13 x 12 / 20 x 20 x 16 / 13 x 13 x 30 / 20 x 20 x 25 / 31 x 39 x 18 | |
| Solar / Reactor / Extractor | 20 / 20 / 20 square x 3 / 12 / 14 | |
| Refinery / Vehicle Bay / Shipyard | 33 x 26 / 26 x 26 / 39 x 39 | Shipyard includes a 20 m launch deck |
| Sensor Mast | 13 x 13 x 90 | tallest object; priority bombing target |
| Outpost / Relay Station / Core | 33 / 39 / 44 square x 20 / 14 / 30 | |
| Boulders / ice spires / ore crystals | 2-9 m / 8-40 m / 3-12 m | props |

### 1.3 Silhouette rules per class

| Class | Planform and key cue | Must not look like |
|---|---|---|
| Dart | Arrowhead delta, twin canted tail fins, one rear engine pod. Fast, narrow. | any three-stacked-wing shape (IP rule) |
| Lancer | Wide "H" planform, twin booms, chin cannon, rocket pods on wing tips. | Dart scaled up |
| Bomber | Fat manta flying wing, ventral bomb bay bulge, four engines. Largest span. | Hauler |
| Scout | Needle fuselage, long thin fins, no payload bulges. | small Dart |
| Hauler | Boxy cargo pod between two booms, forward tether boom, ring cradle. Reads as "truck". | Bomber |
| Harvester | Squat 6-wheel crawler, scoop front, tall rear hopper. | structures |
| Siege Crawler | Low long hull, one large raised barrel at 30 degrees. | Rail Lance |
| Structures | Tall thin = Pylon, Mast, Missile Tower. Wide flat = Pad, Solar. Dome + short barrels = Autocannon. Tall upturned barrel cluster = Flak. Ring on pillar = Shield. Long barrel on plinth = Rail Lance. | |

**Silhouette test (acceptance):** render each ship from top, side and three-quarter at 48 x 48 px, black on white, and have a vision-capable agent classify them against the class list without names. Pass: >= 90 % correct, and no two ships confused with each other in either direction.

**Landing pose (tail-down, 01 s3.1.4; owner decision O-2).** Ships land on their main engine and settle tail-first, so every ship is also designed as a **nose-up parked object**. All five ships carry three fixed landing struts on the tail (`HP_Gear_0..2`, 120 degrees apart around the engine axis, each a thin 3-sided prism ending in a foot plate, `hull_600` with `hull_800` feet), splayed about 20 degrees outward. The foot circle (radius in the table of 4.5) is at most 40 % of the smallest `pad_radius_m` (10 m) so a ship always stands inside the painted landing circle; the centre of mass sits above the foot circle, so the parked ship is visibly stable. Struts are static in v1 (no retraction animation, they add to the planform in flight by design: they read as a tail cluster). Nothing on the dorsal or ventral surface may touch the pad when the ship stands on its struts. In flight the engine flame points down in the hover; `vfx_exhaust_cone` scales with thrust, so a hovering ship already shows a long flame. **Landing-pose acceptance** (added to the silhouette test): a side render of every ship, nose up and standing on a Pad, shows all three feet on the pad plane within 5 cm, and every wing or boom tip within 12 m of the pad-centre axis (the Bomber's 20 m span is the limiting case and fits the 26 m Pad slab).

### 1.4 Readability by camera tier

Apparent length in pixels `px = S * 1080 / (2 d tan(fov/2))`, assuming 1080p and 60 degrees vertical FOV (about `935 * S / d`; 06 owns the real FOV, see Cross-doc dependencies).

| Tier | Distance | Dart (12 m) | Core (44 m) | Art consequence |
|---|---|---|---|---|
| Chase | 35 m | 320 px | - | Full detail, emblem, engine flame, damage smoke |
| Tactical low | 300 m | 37 px | 137 px | LOD0/LOD1, emblem invisible; team colour and planform carry identity |
| Tactical high | 2,500 m | 4.5 px | 16 px | Mesh is a few pixels; world marker (06) takes over |
| Commander | 14,000 m | 0.8 px | 2.9 px | Markers only; terrain and Cores are the picture |

Rules: swap to the `<PascalId>Far` mesh (<= 48 tris, flat team colour) when the body is under 24 px (Dart about 470 m); hide the mesh at 3 px (distance = 312 x length, Dart about 3.7 km). Team colour zones are >= 6 % and <= 35 % of a model's surface so they survive minification.

### 1.5 Lighting model (Compatibility)

All spatial materials share `godot/src/presentation/shaders/moon_light.gdshaderinc` (code, not an LFS asset; written by ART-01, library by ART-03; the planet renderer includes it). Everything is rotationally symmetric about the Z axis, so all 8 start slots light identically. **Compatibility colour space (ART-01 measured, R0 B.11 A-58):** Godot 4.7 Compatibility treats `ALBEDO` and `EMISSION` as sRGB-encoded (decode polynomial `x(x(0.3053x + 0.6822) + 0.01252)`, approximate pow re-encode), so a shader that writes linear constants renders far too dark (the interim moon was near black, night mare -59 %). The include therefore converts inputs with `ml_to_linear`, writes `ALBEDO` / `EMISSION` through `ml_encode` (polynomial inverse, two Newton steps) and puts ambient and earthshine in `EMISSION`; every shader built on the include follows this and never writes a bare linear constant.

| Term | Value | Notes |
|---|---|---|
| Sun | one `DirectionalLight3D`, light travels -Z, colour `#FFF1DC`, energy 1.25 | Physically the equator receives zero sun; see wrap |
| Wrap diffuse | `d = clamp((N.L + w)/(1 + w), 0, 1)`, **w = 0.30** | Implemented in a `light()` function; bases on the terminator get 23 % sun instead of black |
| Radial hemisphere ambient | `mix(#2B3142 x 0.22, #8EA0C8 x 0.38, 0.5 + 0.5 N.up)`, `up = normalize(world_pos)` | Top faces are lit "from above" everywhere on the sphere, which is the single biggest readability win |
| Earthshine | colour `#9DB6E8`; `k = (0.45 + 0.55 max(0, -n.z)) * nf`, `nf = 1 - smoothstep(-0.10, 0.18, dot(n, sun_dir))` (equals `n.z` while the sun is on +Z), `n = up` | Added in `fragment()` as `albedo * earth * **0.50** * k` (ART-01 tuned the 0.55 gain to 0.50 inside the +-20 % band to meet the night-mare target, A-58). Strongest at the Midnight Pole, 45 % at the terminator, zero on the day side |
| Shadows | sun only; 2 splits, max 800 m, PC HIGH tier only (03 s13 takes this distance) | Off on mobile/web |
| Sun direction | global shader uniform `sun_dir` (default +Z; the light travels `-sun_dir`) | Driven by the moving-sun rule in campaign/custom (`rules_overrides.sun_period_s`); wrap, ambient and limb terms read it, earthshine stays tied to Earth at -Z |
| Environment | no glow, no SSAO, no fog, no tonemap; exposure 1.0 | LDR |
| Limb rim | day side only: `albedo += #BFC9E0 * pow(1 - N.V, 3) * 0.20`, **faded in by camera height between 1.5 and 4.5 km** (ART-01: the literal rim washes out dark terrain near the horizon at Chase and Tactical heights; the fade band is an owner taste check, HUM-09, A-58) | Reads the curvature from orbit |

Targets *(anchors, tuned in ART-01 within +-20 %)*: night-side mare renders at about `albedo x (0.30, 0.36, 0.55)` in linear light at the Midnight Pole; every team colour keeps >= 3:1 contrast ratio against night mare and space.

**Sky.** `shader_type sky`: black space, hash-based stars (3 magnitudes, no twinkle), sun disc 2 degrees at `sun_dir` (+Z by default), and **Earth** as a full disc of 6 degrees (art-scaled; true size is about 1.9 degrees; value fixed by R0 C2-31) exactly at -Z, directly above the Midnight Pole, with procedural ocean `#3F6FB5`, cloud swirl and land blobs. Design gift: from any equatorial base the sun sits on the northern horizon and Earth on the southern horizon, so "Earth side = south = night = ice" orients players without a UI.

---

## 2. Palette and colour

### 2.1 Neutral and biome palette

Biome ids are the u8 values of the baked biome faces (Section 9.3). Each biome has a 3-stop ramp (low / mid / high) sampled by a per-pixel shader value (Section 3.1). Rendered night colour is `albedo_linear x (0.30, 0.36, 0.55)`.

| Id | Biome | Low | Mid | High | Notes |
|---|---|---|---|---|---|
| 0 | `mare` | `#30343F` | `#404552` | `#51576A` | dark basalt basins |
| 1 | `highland` | `#7A7770` | `#959189` | `#B1ACA1` | anorthosite |
| 2 | `crater_floor` | `#2A2C34` | `#353840` | `#43474F` | darker than mare, warmer |
| 3 | `rim_ejecta` | `#A8A396` | `#C0BBAE` | `#D6D1C4` | brightest natural surface; rays |
| 4 | `cold_trap` | `#34485E` | `#5B7C9E` | `#B5D8EC` | night side only; frost speckle |
| 5 | `ore_field` | `#6B5B3F` | `#8D7648` | `#AA9158` | ochre, chroma about 32 |
| 6 | `solar_plateau` | `#B9B5AA` | `#D0CCC0` | `#E3DFD2` | day side only; faint tile grid |
| 7 | `rille_floor` | `#22242B` | `#2C2F37` | `#373B44` | darkest |
| 8-15 | reserved | | | | |

Space `#05070C`. Sun `#FFF1DC`. Earthshine `#9DB6E8`.

### 2.2 Team colours (8 slots, each with a shape)

Slot order is the *assignment order*: 1v1 uses slots 0-1, 2v2 uses 0-3, so the most distinguishable colours serve the most common games. Colours are rendered unlit in team zones. Shapes are used for ship and structure emblems (3D, 32 px cells in the atlas) and for the outer frame of every world/UI marker (06).

| Slot | Name | Hex | Shape | Deut. sim | Prot. sim | Trit. sim | L* |
|---|---|---|---|---|---|---|---|
| 0 | Amber | `#E1A633` | circle | `#CBB638` | `#BDA81F` | `#F59590` | 72 |
| 1 | Cobalt | `#4C64ED` | triangle | `#006BEA` | `#0079F2` | `#00869F` | 48 |
| 2 | Mint | `#3BFAB2` | square | `#DFD7B7` | `#F6E7AE` | `#00FAE7` | 88 |
| 3 | Forest | `#17840E` | diamond | `#7C6F1F` | `#877700` | `#008070` | 48 |
| 4 | Magenta | `#B1369D` | cross | `#60719A` | `#365EA0` | `#BA3F65` | 45 |
| 5 | Orchid | `#E9A1FD` | star (5 point) | `#A6BEFA` | `#94B7FF` | `#EAACC3` | 76 |
| 6 | Lime | `#D6F72C` | chevron (V) | `#FFE943` | `#FFE800` | `#E3E9D3` | 92 |
| 7 | Coral | `#F06867` | ring | `#AB9E64` | `#898266` | `#FF5069` | 61 |

**Allegiance is not carried by hue.** The CVD simulation shows warm/cool grouping fails (Mint and Forest both collapse toward yellow under deuteranopia). Friend/foe uses a separate channel: solid frame = own/allied, four-corner brackets = enemy, dashed = neutral (06 implements; see Cross-doc dependencies). 07 owns colour (R0 C2-21): world emissives and markers use the slot colours and shapes above in this order; 06 A11Y-01 cites this table.

**Preset variant "Relation colours" (06 A11Y-02).** For players who want hue-coded relations, `palette.json` carries a second variant `relation`: three colours `ally`, `enemy`, `self` from the Okabe-Ito set (starting values ally `#0072B2`, enemy `#D55E00`, self `#F0E442`; ART-02 may nudge lightness), applied to markers, frames' fill and unit team zones instead of the slot colours. The shape cue and the frame styles stay on. `cvd_check.py` checks the variant like the main palette: pairwise CIEDE2000 among ally/enemy/self >= 20 under each CVD simulation, and each against hull swatches and the UI plate >= 20.

### 2.3 How the team palette was checked

**Method (reproducible by `tools/art/cvd_check.py`, task ART-02).** For each colour: sRGB to linear; apply the Machado, Oliveira and Fernandes 2009 simulation matrices at severity 1.0 for protanopia, deuteranopia and tritanopia (full dichromacy, the hardest case) in linear RGB; convert to CIELAB (D65); measure **CIEDE2000** between every pair (28 pairs) under normal vision and each simulation. Cross-check: Vienot, Brettel and Mollon 1999 matrices for protan/deutan. The palette was found by simulated-annealing search over an LCh candidate grid (maximise the minimum pair distance over all four vision types, with normal-vision distance weighted to force hue diversity), then refined against the terrain.

**Results (all 28 pairs).**

| Test | Threshold | Result |
|---|---|---|
| Team vs team, normal vision | >= 20 (R0 C1-11) | min 25.1 (Cobalt/Magenta) |
| Team vs team, protanopia | >= 11.0 (R0 C1-11) | min 13.1 (Cobalt/Magenta); Vienot 12.9 |
| Team vs team, deuteranopia | >= 11.0 | min 12.0 (Amber/Coral); Vienot 12.4 |
| Team vs team, tritanopia | >= 11.0 | min 13.6 (Amber/Coral) |
| Relation colours (ally / enemy / self), each CVD | >= 20 | checked on the `relation` variant (Section 2.2) |
| Slots 0-3 only (the 2v2 case) | >= 15 | min 17.0 |
| Slots 0-1 only (1v1) | >= 40 | min 55.3 |
| Team vs rendered terrain (day/night states that exist for the biome, plus space), normal | >= 17 | min about 17 (Cobalt on night cold trap) |
| Team vs rendered terrain, any CVD | >= 7 | min 7.0 (Mint on plateau, deutan) |
| Team vs `hull_700` / UI plate `#0F141C` (all vision) | >= 20 | min 23.7 / 29.3 |

**What this does and does not prove.** A CIEDE2000 above 10 means the colours are clearly different for large patches. For a dichromat, eight colours cannot all be separated by hue alone; the weakest pairs depend on lightness. Therefore: (1) the shape cue is mandatory, never optional; (2) team zones sit next to dark hull swatches (`hull_500`-`hull_800`) and markers sit on a dark plate, because `hull_100` is only 9.7 from Lime; (3) the 5-8 player case relies on shape and the allegiance frame as well as hue. The check is re-run by CI (ART-02) on any change to `palette.json`; a drop below a threshold fails the build. A human tester with CVD should confirm in ART-33 (golden scenes with all 8 colours).

### 2.4 UI and resource palette

| Token | Hex | Use |
|---|---|---|
| `ui_bg_0` / `ui_bg_1` / `ui_bg_2` | `#080B10` / `#0F141C` / `#18202C` | screen, panel (78 % alpha over world), raised |
| `ui_line` | `#2B3748` | 2 px strokes, corner brackets |
| `ui_text` / `ui_text_dim` | `#E6EBF2` / `#98A4B6` | text (contrast on `ui_bg_1` 14:1 / 6.9:1) |
| `ui_accent` | `#5CC8FF` | primary buttons, focus; 31 from the nearest team colour |
| `ui_focus` | `#FFFFFF` | selection rings, keyboard focus |
| `ui_ok` / `ui_warn` / `ui_danger` | `#6FD08C` / `#FFC247` / `#FF5A5A` | status accents; **always paired with icon shape (circle-check / triangle-! / octagon-x) and text**; never used to tint an entity |
| `res_ore` / `res_ice` / `res_power` | `#C8A25E` / `#8FD3F2` / `#FFF0A0` | resource icons and bars (hex, droplet, bolt shapes) |

Placement ghost: valid = solid `ui_accent` hologram; invalid = diagonal-hatch pattern in `ui_danger`. Pattern, not hue, carries the state.

---

## 3. The procedural moon look

03 owns the planet renderer code; 07 owns what it must look like and supplies the data below. Detail is shader-only and never changes `Terrain.height_at()`.

### 3.1 Terrain material (`moon_terrain.gdshader`)

| Input | Source | Use |
|---|---|---|
| Biome id | baked u8 face texture (nearest filter), 6 faces | selects ramp row |
| Ramp value `v` | `0.55 * fbm(pos * 0.015) + 0.30 * (1 - slope01) + 0.15 * cell(pos * 0.12)` | position on the 3-stop ramp |
| Ramp LUT | `moon_ramp.png`, 16 x 64 RGBA8, generated from `biome_ramps.json` by `tools/moonbake/` | colour |
| Small craters | Voronoi bowl+rim at three scales (40 / 15 / 6 m), amplitude <= 1.2 m total, mean zero | vertex displacement + albedo darkening in bowls |
| Day/night | `moon_light.gdshaderinc` | Section 1.5 |

Visual displacement is at most 1.2 m; every structure carries a foundation skirt (Section 4.2) of at least 0.6 m depth (R0 C2-31, replaces 03's plate numbers), and the terrain shader fades displacement to <= 0.6 m inside structure footprints (03 implements), so nothing floats or sinks visibly. Frost speckle on `cold_trap`: sparse bright texels, static (reduced-motion safe).

### 3.2 Feature visual language

| Feature | Treatment |
|---|---|
| Maria | smooth, dark, almost no small craters (density x 0.2); wrinkle ridges as soft lighter lines |
| Craters (baked) | rim biome `rim_ejecta` ring 0.12 x radius wide; floor `crater_floor`; terraced wall via slope term; ejecta rays = 8-14 streaks of `rim_ejecta` out to 3 x radius |
| Highlands | rough: small-crater density x 3, ramp noise amplitude x 1.5 |
| Rilles | `rille_floor` strip plus a light lip line; flagged landmarks so players can use them as corridors |
| **Cold Trap** | crater with `cold_trap` floor, 3-5 ice spire props (pale `#B5D8EC` crystals, 8-40 m), thin frost ring at the lip; the *only* cool-blue surface on the moon, so it reads instantly |
| **Ore Field** | `ore_field` patch with mottled edge, 6-20 ochre crystal-cluster props; prop count tracks remaining ore (field at 30 % shows 30 % of props) |
| **Solar Plateau** | pale, perfectly smooth, 100 m tile lines; six low corner markers; Relay Station at centre |
| Midnight Pole | ring of tall ice spires visible from orbit; Earth overhead |
| Boulder fields | MultiMesh of 3 boulder meshes, density from the baker's `boulder_fields` list; no collision for ships (s5.4) |
| Scorch marks | surface-aligned quad 0.4 m above the surface (no Decal nodes in 4.7). Interpretation of 01 ADR-02 "camera-facing quads": a camera-facing billboard lying on terrain would look wrong; depth precision at 0.4 m offset holds out to 2 km. Replaced by real Decals after the 4.8.1 upgrade |

### 3.3 Props

All props <= 80 tris (spires <= 60, boulders <= 48). Scattered with the deterministic `Rng` (PCG32) from the map seed; clients may differ in prop placement without any gameplay effect, but we use the shared seed so screenshots are reproducible.

---

## 4. Asset pipeline (Blender MCP to Godot)

### 4.1 Principle: scripts are the source

An agent does **not** model by hand-driving the viewport. Each asset is a deterministic Python recipe `tools/blender/recipes/<asset_id>.py` that builds the mesh with `bpy`/`bmesh` from the dimensions on the recipe card, runs through the Blender MCP `execute_blender_code` tool (or headless `blender -b -P`), and exports the `.glb`. The MCP's viewport tools (`get_objects_summary`, `render_viewport_to_path`, `get_screenshot_of_area_as_image`) are for *looking* at the result. Reasons: reviewable diffs, variants by changing a parameter, reproducible rebuilds, and Haiku-tier agents can edit numbers but cannot reliably sculpt. Committed: recipe `.py` and the exported `.glb` (LFS). `.blend` files are not committed.

**MCP safety rule (from the Blender MCP server instructions):** never destructively modify an existing scene. A recipe starts with `pw.begin(asset_id)`, which creates a new collection `PW_<asset_id>` in the current file and removes only a previous collection of the same name. Run recipes in a dedicated working file.

### 4.2 Universal conventions

| Item | Rule |
|---|---|
| Blender | 4.2 LTS or newer (4.5 LTS recommended). Metric, unit scale 1.0 = 1 m. |
| Axes in Blender | Z up. **Ships: nose toward +Y** (becomes -Z after glTF Y-up export, which is Godot forward and the `Basis` forward of 01 s3.1.1). Wings along X. Structures face +Y (front door/barrel side). |
| Origin | Ships and ground units: centre of the hull bounding box (the sim's bounding-sphere centre). Structures: centre of the footprint at ground level (y = 0); the foundation skirt extends below 0. Props: centre of base. |
| Applied transforms | Scale 1, rotation 0 on every object; modifiers applied at export. |
| Geometry | Build one half (X >= 0) and mirror, then apply. Flat shading (`shade_flat`). No bevel except on Core (1 segment, key edges only). Adjacent non-coplanar faces differ by >= 20 degrees; coplanar leftovers removed with `dissolve_limited(angle_limit=radians(1))`. Triangulate at export. |
| Material | Exactly one material per asset, named `PW_Atlas`. No images embedded. |
| Hardpoints | Empties named `HP_*` (e.g. `HP_Nose`, `HP_Tail`, `HP_Muzzle_L`, `HP_Exhaust_0`, `HP_Bomb_0`..`HP_Bomb_5`, `HP_Rocket_0`.., `HP_Tether`, `HP_Dock`, `HP_Light_0`, and on every ship the three tail landing struts `HP_Gear_0..2` at the foot-plate centres). Plain axes, size 0.5. `HP_Nose` and `HP_Tail` are on the thrust axis; `HP_Tail` sits at the engine nozzle, between the struts. |
| Parts that move | Separate objects: tower `Turret` (yaw) and `Barrel` (pitch); Hangar `Roof`; Shipyard `Arm_L/R`. Rigid sub-nodes only; no skeletal animation in v1 (animated in code). |
| Foundation | Every structure has a mesh part `Foundation`: its footprint extruded down by `max(0.27 x half_footprint, 0.6 m)` (tan 15 degrees, the maximum placement slope; 0.6 m minimum for small structures), flat swatch `hull_700`. |
| Far mesh | Each unit and every structure over 15 m has a `<PascalId>Far` object (<= 48 tris, single swatch family, team zone as one swatch). |

### 4.3 Palette atlas, UV method, team mask

Single source of truth: `tools/blender/palette.json`; `tools/blender/build_palette.py` generates `godot/assets/textures/unit_atlas.png`.

- **Atlas size 256 x 256 RGBA8, lossless, mipmaps on.** This sits far below the 2,048^2 ceiling of 01 s8.2 (256 KB instead of 16 MB). The ceiling is kept as headroom for a v1.x emblem/paint sheet.
- Swatch grid: 16 columns x 14 rows of 16 px (224 swatches). Rows 14-15 (y 224-255) hold the **emblem strip**: 8 emblems of 32 x 32 px, white shape on dark, one per team shape (Section 2.2).
- **UV-to-swatch method:** every face's three UVs are set to the *centre of one swatch cell* (`u = (col+0.5)/16`, `v = (row+0.5)/16`). Result: flat colour, no texture bleed, zero UV derivative so the GPU always samples mip 0. Helper `pw.paint(faces, "hull_300")` does this.
- **Team mask lives in the atlas alpha channel** as a 2-bit class code, decoded in the shader by `int c = int(round(a * 3.0))`:

| Alpha | Code | Meaning | Shader result |
|---|---|---|---|
| 0 | 0 | plain | `ALBEDO = rgb`, lit |
| 85 | 1 | team paint | `ALBEDO = team_color * rgb.r`, lit (rgb is a grey shade: `team_paint_hi/mid/lo`) |
| 170 | 2 | emissive accent | `EMISSION = rgb` (engine flame, glass lights) |
| 255 | 3 | team glow | `EMISSION = team_color * rgb.r`, unlit; **exact hex of Section 2.2 at `rgb.r = 1`** |

- **Emblem:** a quad whose UVs map into emblem cell 0 (v >= 0.875). The shader adds `team_index * 0.125` to `u` for that region.
- **Per-instance parameters** (Godot `instance uniform`, supported in Compatibility per the 4.7 shader reference, which documents a Compatibility workaround for sampler arrays; ART-01 verifies on WebGL2 and Adreno): `team_index:int`, `team_color:vec3`, `build_progress:float`, `damage01:float`, `wreck:float`. One shared `unit_lit.tres` serves every unit and structure. **Fallback chosen (ART-01, R0 B.11 A-58):** `instance uniform` on Compatibility is pending the Adreno / WebGL2 device run (HUM-06), so v1 ships the per-material path: `UnitMaterialCache` (presentation, ART-03) holds one `unit_lit` `ShaderMaterial` per (team 8 x state 5) = 40 materials created lazily, plus a `build_material(team, build_progress)` variant; `unit_lit_instanced.gdshader` keeps the instance-uniform body (`#define UNIT_PARAM instance uniform`) for a v1.x switch if HUM-06 passes everywhere. The planned fallback of "eight material copies via `material_override`" is this cache. Cosmetic hull paints (3.4 of 01) are alternate 256 px atlases swapping the `hull_*` rows (v1.x).
- Swatch families in `palette.json` (about 45 entries): `hull_100`..`hull_800` (`#E4E7EC`, `#C5CAD3`, `#9AA2B1`, `#6E7686`, `#4B5262`, `#333846`, `#232733`, `#151821`), `metal_gun` `#5A5F6B`, `glass` `#1C3442`, `glass_emit` `#7FD6FF` (code 2), `engine_emit` `#CFEBFF` (code 2), `tyre` `#1B1D24`, `solar_cell` `#1B2A4E`, `solar_frame` `#8A93A6`, `ore_rock` `#A68646`, `ice_rock` `#9CCDE3`, `power_emit` `#FFF2B0`, `team_paint_hi/mid/lo`, `team_glow`, `team_glow_dim`, and the 8 emblem cells. **Rule:** no saturated hull swatch exists, so team colours stay unique. Team zones touch only `hull_500`-`hull_800`.

### 4.4 Helper library API (`tools/blender/lib/pw.py`, task ART-04)

```python
def begin(asset_id: str, cls: str) -> bpy.types.Collection        # new collection PW_<id>, sets scene units
def box(name: str, size: tuple, loc: tuple, swatch: str, taper: float = 1.0) -> bpy.types.Object
def prism(name: str, sides: int, r0: float, r1: float, length: float, axis: str, loc: tuple, swatch: str) -> bpy.types.Object
def poly_plate(name: str, pts: list, thickness: float, loc: tuple, swatch: str) -> bpy.types.Object  # delta wings, fins
def paint(obj: bpy.types.Object, swatch: str, faces: list | None = None) -> None    # UV-to-swatch
def mirror_x(objs: list) -> None                                    # mirror and apply
def hardpoint(name: str, loc: tuple) -> bpy.types.Object
def emblem_quad(name: str, size: float, loc: tuple, rot: tuple) -> bpy.types.Object
def foundation(footprint: tuple) -> bpy.types.Object                 # depth max(0.27 x half_footprint, 0.6 m)
def landing_struts(length: float, foot_radius: float, around: list) -> list   # ships: HP_Gear_0..2 on the tail, flat swatches
def far_mesh(source: list, target_tris: int = 48) -> bpy.types.Object  # decimate copy, repaint to one swatch family
def finalize(asset_id: str) -> dict       # join per rules, dissolve, flat shade, triangulate count, validate; returns report
def export_glb(asset_id: str, out_dir: str) -> str
```

`finalize()` returns the same report fields as the glb validator (Section 4.7) so the agent sees failures before exporting.

### 4.5 Recipe cards (primitive blockout)

Dimensions in metres, half model (mirrored) unless noted. Tri counts are the target; the validator enforces the ceiling.

**Tail landing struts (all five ships, tail-down landing, 01 s3.1.4).** Each ship recipe ends with `pw.landing_struts(length, foot_radius, around)`: three struts `HP_Gear_0..2` (3-sided prisms, splayed 20 degrees, 4-triangle foot plates, about 30 tris in total, inside the ship's budget). The struts extend behind the nozzle plane, so they lengthen the bounding box by at most 10 % (V08 tolerance). Per ship (strut length / foot-circle radius): Dart 1.1 / 1.6; Lancer 1.5 / 2.4; Bomber 2.2 / 4.0; Scout 0.8 / 1.0; Hauler 2.0 / 3.0. Placement: Dart and Scout around the single engine; Lancer and Hauler one on each boom end plus one on the centre pod; Bomber on the two outer trailing-edge engines plus the centre. In the **Dart style frame** (ART-06) the landing pose (nose up on a Pad, hover flame down) is rendered as one of the two owner-review images.

| Asset | Blockout steps | Team zones |
|---|---|---|
| **Dart** (<=600) | Fuselage 6-sided prism 12 long, r 0.9 to nose 0.15; delta wing plate (5 pts, span 9, thick 0.25) swept 55 degrees; two tail fins plate 2.2 tall canted 25 degrees; engine hex prism r 0.8, length 1.6 with `engine_emit` cap; canopy 4-sided pyramid 2.4 long `glass`; tail landing struts (see above). | wing top outer 60 % paint; fin outer faces glow strip; emblem quads on wing tops |
| Lancer (<=900) | Two boom prisms 14 long r 0.8 at x = +-3; centre pod box 6 x 2.4 x 2.6; wing plate span 12 joining booms; chin cannon prism r 0.35, length 4; two rocket pod boxes at wing tips; tail landing struts | wing top, boom stripes |
| Bomber (<=1,200) | Flat manta wing plate (9 pts, span 20, thick 1.2); ventral bay box 6 x 3.5 x 1.6 `hull_600`; four engine hex prisms on the trailing edge; short nose canopy; tail landing struts | wing outer thirds glow strips |
| Scout (<=450) | Needle prism 8 long r 0.5 to 0.1; two fin plates span 6; antenna prism 2 long; tail landing struts | single glow stripe |
| Hauler (<=900) | Cargo box 9 x 5 x 5; two boom prisms 14 long; forward tether boom prism 6 long with `HP_Tether` underneath; ring cradle (8-sided torus, 12 tris/seg budget) under hull; 2 engines; tail landing struts | cargo box side panels paint |
| Harvester (<=700) | Hull box 7 x 4 x 1.8; 6 wheel octagon prisms r 0.9; scoop wedge front; hopper box 3 x 3.5 x 2.6 rear with `ore_rock` fill face | hull top paint, hopper stripe glow |
| Siege Crawler (<=900) | Hull box 12 x 6 x 2; 8 wheel prisms; barrel prism r 0.6 length 9 on a block, pitched 30 degrees (sub-object `Barrel`) | hull sides |
| Core (<=3,000) | Foundation; base slab 44 x 44 x 3; central tiered hex tower to 30 m in 3 steps; four corner buttress prisms; ring pad deck 24 m across (`pad_radius_m` 12) with the integrated-shield emitter ring around the tower base (the dome itself is `vfx_shield_dome`); bevel 1 seg on slab and tower edges | tower band glow, four corner pennants (emblem boards) |
| Outpost (<=2,000) | Foundation; slab 33 x 33 x 2; short hex tower 20 m; pad deck 20 m across (`pad_radius_m` 10) | tower band |
| Pylon (<=300) | Foundation 4 m; tapering 4-sided mast to 30 m; three ring flanges; top cap | top ring glow |
| Solar (<=600) | Foundation; 3 x 3 panel tiles 6 x 6 tilted 12 degrees on stub posts; frame boxes | frame corner dots |
| Reactor (<=900) | Foundation; squat 8-sided cylinder r 7 h 12; 4 cooling fins; top vent; `power_emit` ring | ring glow |
| Refinery (<=1,500) | Foundation; process hall box 33 x 20 x 10; two tanks (8-sided prisms r 5 h 12); intake funnel on +Y; pipe boxes | hall roof stripe |
| Ice Extractor (<=800) | Foundation; wellhead box 6 x 6 x 6; 3 pipe prisms into ground; small tank | cap glow |
| Pad (<=500) | Slab 26 x 26 x 0.8; painted landing circle of radius `pad_radius_m` 10 (flat swatch ring, 0.1 m raised); inset ring of 12 edge lights (`HP_Light_*`); central H mark as 6 raised faces (the ship's tail stands on it); `HP_Dock` at centre = tail socket | edge light strips |
| Hangar (<=1,100) | Pad slab with the same landing circle (radius 10); walls and flat bomb-proof roof box 26 x 26 x 9; sliding roof panel `Roof` | door frame |
| Shipyard (<=1,500) | Foundation; hall box 39 x 20 x 14; 20 m launch deck with edge lights; gantry arms `Arm_L/R` prisms | hall band, arm tips |
| Vehicle Bay (<=1,300) | Foundation; low hall 26 x 22 x 9; ramp wedge on +Y | roof band |
| Sensor Mast (<=700) | Foundation; 3-leg lattice approximated by 3 tapering prisms to 90 m; dish (6-sided cone) at 80 m; blink `HP_Light_0` | dish rim glow |
| Autocannon (<=600) | Foundation; hex base r 5 h 3; dome turret r 3.5 (`Turret`); two barrel prisms length 5 (`Barrel`) | dome band |
| Flak (<=800) | Foundation; wide base; turret box; four barrel prisms length 9 pitched 65 degrees | turret band |
| Missile Tower (<=800) | Foundation; tapering mast to 24 m; angled 4-tube pod `Turret` on top | pod band |
| Shield Projector (<=800) | Foundation; pillar to 20 m; 12-segment ring (r 8) on top; `HP_Dome` at ring centre | ring glow |
| Rail Lance (<=1,200) | Foundation 31 x 39 (footprint 4 x 5 cells); plinth 12 x 12 x 6; long barrel box 39 x 2 x 2 on a pitching mount (`Barrel`) | barrel rails glow |
| Relay Station (<=1,500) | Foundation; pad 24 m across (`pad_radius_m` 12); central mast 14 m with 3 dishes; neutral: team zones use `hull_400` until captured (shader param `team_index = -1`) | dishes |

**Docked pose.** The sim pose of a DOCKED ship is the nose-up landing pose with the tail on `HP_Dock`. On an open Pad, Outpost, Core, Relay Station or Shipyard deck the view shows exactly that. On a **Hangar** (9 m hall; a Dart stands 13 m tall nose-up) the view layer plays a presentation-only stow: the `Roof` slides open, the docked mesh node tips to horizontal and lowers into the hall in 0.8 s after touchdown, and the reverse plays before `LAUNCHED`. The sim pose never changes; the stow is a node transform in `EntityViewPool` (ART-38).

### 4.6 glTF export (Blender) and Godot import

**Export** (`pw.export_glb`, `bpy.ops.export_scene.gltf`). Option names changed between Blender 4.1 and 4.2+; the recipe's first call prints the installed operator's property list (`bpy.ops.export_scene.gltf.get_rna_type().properties.keys()`) and the helper asserts every key it uses exists.

| Setting | Value |
|---|---|
| `export_format` | `GLB` |
| `use_selection` | `True` (only collection `PW_<id>`) |
| `export_apply` | `True` (modifiers, including Triangulate) |
| `export_yup` | `True` |
| `export_normals` | `True` (flat normals) |
| `export_texcoords` | `True` |
| `export_tangents` | `False` |
| vertex colours / custom attributes | none |
| `export_materials` | `EXPORT` |
| `export_image_format` | `NONE` (no embedded images) |
| cameras, lights, animations, skins, morph | `False` |
| `export_extras` | `True` (hardpoint types) |
| Draco compression | off (Godot cannot import it) |

**Import** (committed `<asset>.glb.import`, written by `tools/art/write_import.py` from a template that ART-05 captures once from the Import dock so key names are exact):

| Option | Value |
|---|---|
| `nodes/root_type` | `Node3D` |
| `nodes/apply_root_scale` / `root_scale` | `true` / `1.0` |
| `meshes/ensure_tangents` | `false` |
| `meshes/generate_lods` | `true` |
| `meshes/create_shadow_meshes` | `true` (units and structures), `false` (props) |
| `meshes/light_baking` | Disabled |
| `animation/import` | `false` |
| `import_script/path` | `res://assets/_pipeline/post_import_asset.gd` |

`post_import_asset.gd` (an `EditorScenePostImport`): converts `HP_*` Node3Ds to `Marker3D`; assigns `visibility_range_end` per class (Section 1.4); applies `<PascalId>Far` visibility ranges; turns shadows off for props and `Far` meshes; assigns the shared `unit_lit.tres`; prints the triangle count and warns above budget.

**LOD.** Godot generates mesh LODs at import (meshoptimizer; screen-coverage selected). The project setting `rendering/mesh_lod/lod_change/threshold_pixels` is 1.0 on PC and 3.0 on mobile/web quality tiers. Gate (ART-36): render LOD1/LOD2 at their switch distance; silhouette overlap with LOD0 must be >= 90 %, otherwise the asset gets an authored `<PascalId>Far` replacement and `generate_lods` is disabled for it. The `<PascalId>Far` meshes are separate from Godot's LODs because they have a different purpose: the far pool (Section 5.3).

### 4.7 Validation script spec

Authoritative gate: **`tools/art/validate_glb.py <file.glb>`** (pure Python, parses the GLB JSON and BIN chunks with numpy, no Blender needed in CI). Class budgets in `tools/art/asset_budgets.json`. Output: JSON report and exit code 0/1. Mirror in Blender: `finalize()` runs the geometry checks early.

| Check | Rule |
|---|---|
| V01 name | file = `<asset_id>.glb`, `^(ship|gnd|str|prop|proj|wreck)_[a-z0-9_]+$` |
| V02 root | one root node named PascalCase of the id (`ShipDart`), identity transform |
| V03 triangles | sum over all meshes of the asset, **including its `<PascalId>Far` mesh** (Far triangles count toward the budget), <= the asset's `max_tris` in `asset_budgets.json` (class ceiling for unlisted assets); warn if < 25 % of budget |
| V04 material | exactly one material `PW_Atlas`; `images` empty |
| V05 attributes | POSITION, NORMAL, TEXCOORD_0 only; no TANGENT, COLOR_0, TEXCOORD_1, skins, animations |
| V06 swatch rule | all three UVs of each triangle within 1e-4 of one swatch centre (except emblem quads with v >= 0.875) |
| V07 flat | vertex normal equals face normal within 1e-3 |
| V08 size | bounding box within +-10 % of the Section 1.2 scale chart |
| V09 origin | ships: bbox centre within 0.5 m of origin; structures: XZ centre within 0.5 m, min Y in [-foundation_max, 0] |
| V10 forward | ships: node `HP_Nose` has smaller Z than `HP_Tail` |
| V11 hardpoints | required `HP_*` list per asset in `asset_budgets.json`; every ship requires `HP_Nose`, `HP_Tail`, `HP_Gear_0..2` (feet coplanar within 5 cm, centroid within 0.3 m of the thrust axis); every pad-bearing structure requires `HP_Dock` |
| V12 degenerate | no zero-area triangles |
| V13 file size | `.glb` size <= the class `max_file_kb` in `asset_budgets.json`: ship 150 KB, gnd 150 KB, str 300 KB (structures incl. Core), prop 50 KB, proj 20 KB, wreck 50 KB |
| V14 team area | team swatch area (alpha code 1 or 3, from `palette.json`) between 6 % and 35 % of surface |
| V15 names | node names `[A-Za-z0-9_]` only; moving parts and `<PascalId>Far` present where `asset_budgets.json` requires them |

### 4.8 How a Haiku agent adds a variant

Variants (a new paint scheme, a Doctrine pennant, a size change) are *parameter edits*: copy `recipes/ship_dart.py` to `recipes/ship_dart_b.py`, change the dict at the top of the file (`DIMS`, `SWATCHES`, `TEAM_ZONES`), run it through the MCP, run `validate_glb.py`, add the def's `presentation.mesh` path. No geometry code is touched. Anything that needs new geometry is Sonnet-tier.

---

## 5. v1 asset inventory and production estimate

### 5.1 Models

Tier = tier of the producing agent; hours = agent-hours including 0.5 h review by a vision-capable reviewer. Modelling quality is the risk of the Haiku column; the validator and the silhouette test are the safety net (Section 1.3). "Far" counts as one extra mesh already included.

| Asset id | Class | Tris | LODs | Hours | Tier |
|---|---|---|---|---|---|
| `ship_dart` | hero ship (incl. tail struts) | 600 | 3 + Far | 6.5 | Opus (sets the style for all) |
| `ship_lancer` | ship (incl. tail struts) | 900 | 3 + Far | 4.25 | Sonnet |
| `ship_bomber` | ship (incl. tail struts) | 1,200 | 3 + Far | 5.25 | Sonnet |
| `ship_scout` | ship (incl. tail struts) | 450 | 2 + Far | 2.75 | Sonnet |
| `ship_hauler` | ship (incl. tail struts) | 900 | 3 + Far | 4.25 | Sonnet |
| `gnd_harvester` | ground | 700 | 3 + Far | 3.5 | Sonnet |
| `gnd_siege_crawler` | ground (v1, status `core`) | 900 | 3 + Far | 3.5 | Sonnet |
| `str_core` | hero structure | 3,000 | 3 + Far | 7 | Opus |
| `str_outpost` | structure | 2,000 | 3 + Far | 4 | Sonnet |
| `str_pylon`, `str_pad` | simple structure | 300 / 500 | 2 + Far | 1.5 each | Haiku |
| `str_solar`, `str_reactor`, `str_extractor` | structure | 600 / 900 / 800 | 2 + Far | 2 each | Haiku |
| `str_refinery`, `str_shipyard`, `str_vehicle_bay`, `str_hangar` | structure | 1,500 / 1,500 / 1,300 / 1,100 | 3 + Far | 3.5 each | Sonnet |
| `str_sensor_mast`, `str_autocannon`, `str_flak`, `str_missile_tower`, `str_shield`, `str_rail_lance` | tower/support | 700 / 600 / 800 / 800 / 800 / 1,200 | 2 + Far | 2.5 each | Sonnet |
| `str_relay_station` | neutral structure | 1,500 | 3 + Far | 3.5 | Sonnet |
| `wreck_rubble_s/m/l` | wreck | 80 / 150 / 300 | 1 | 1 each | Haiku |
| `proj_bomb`, `proj_rocket`, `proj_rail_bolt` | projectile mesh | 60 / 80 / 12 | 1 | 1 each | Haiku |
| `prop_boulder_a/b/c`, `prop_ice_spire_a/b`, `prop_ore_cluster_a/b/c`, `prop_debris_a/b/c`, `prop_spire_midnight`, `prop_plateau_marker` | props (13) | <= 80 | 1 | 0.75 each | Haiku |

**Model subtotal: about 98 agent-hours** (Opus 13.5, Sonnet 56, Haiku 28.5). Against the stage-2 draft: `str_silo` removed (-1.5 h, owner cut O-4), tail landing struts added to the five ships (+1.25 h). 25 ship/ground/structure models remain (plus wrecks, projectiles and props); `gnd_siege_crawler` and `str_rail_lance` stay in v1.

### 5.2 Everything else

| Asset class | Count | Hours | Tier |
|---|---|---|---|
| Shaders (`unit_lit`, `prop_lit`, `moon_terrain`, `sky_moon`, `shield_dome`, `vfx_additive`, `hologram_ghost`, `moon_light.gdshaderinc`) | 8 | 28 | Sonnet (Opus review of terrain/sky) |
| VFX effects (Section 6) | 26 | 40 | Sonnet |
| UI icons (class glyphs 26, team shapes 8, resource 3, HUD/alerts/menus about 65) | about 100 SVG | 25 | Sonnet (set), Haiku (variants) |
| Fonts subset and UI theme | 2 families | 6 | Sonnet |
| SFX (Section 8.1) | 78 ids, about 156 files | 31 | Haiku (recipes), Sonnet (tool) |
| Music | 9 loops + 3 stingers | licensed or commissioned (Q-ART1) | human + Sonnet integration 8 |
| Maps | 3 | 24 | Sonnet / Haiku |
| Tooling (palette, validators, helper lib, import, audio synth) | 7 tools | 45 | Sonnet |
| Look-dev and QA spikes | 3 | 30 | Opus |

**Whole content pipeline: about 330 agent-hours** (about 55 agent-days at 6 productive hours).

### 5.3 Frame budgets (mobile reference: 400 k tris, 400 draws)

| Component | Triangles | Draws |
|---|---|---|
| Terrain, 90 chunks x 2,048 | 184 k | 90 |
| Units in view (20 LOD0 x 700, 60 LOD1 x 320, 70 Far x 48) | about 36 k | 150 |
| Structures in view (60, mixed LOD) | about 36 k | 60-100 |
| Props via MultiMesh (boulders, spires, ore crystals) | about 40 k | 8 |
| Projectiles, debris (MultiMesh) | about 5 k | 4 |
| Particles (<= 2,000 quads) | 4 k | about 20 |
| UI (batched canvas) | - | about 40 |
| **Sum** | **about 305 k (76 %)** | **about 380-430** |

The draw-call sum shows the budget is tight, which is why **ART-A1 is accepted** (R0 C1-17, 01 s8.1): on the Reduced, Lite and LOW tiers at most **200** visible entities are individual `Node3D` meshes (nearest first) and the rest draw as `<PascalId>Far` instances through per-class MultiMesh far pools (about 8 draws); Standard keeps 800 nodes. 03 s10.1/s13 implements the far-pool path in `EntityViewPool` (200/400/800 nodes by tier).

---

## 6. VFX (Compatibility renderer notes)

General: `GPUParticles3D` (works, no trails, no SDF collision, R2 s2.2) for bursts; `MultiMeshInstance3D` for anything counted in hundreds; custom ring-buffer **puff trails** instead of particle trails; additive halos instead of glow. All particle nodes are pooled; `one_shot`, `fixed_fps = 30`, `interpolate = false`, `draw_order = none` (no sorting), world-space, with a hand-set `visibility_aabb`. No effect uses `screen_texture` or `depth_texture` (cost and Compatibility gaps). Local lights: one pool of 4 `OmniLight3D` for large explosions (energy 3, 0.3 s), off on low tier.

| VFX id | Technique | Cap (live) | Notes |
|---|---|---|---|
| `vfx_exhaust_cone` | additive stretched cone mesh, length scales with thrust | per ship in 600 m | no particles; 24 tris |
| `vfx_exhaust_burst` | GPU, 12 quads | 24 ships | possessed unit plus nearest 23 |
| `vfx_muzzle_flash` | billboard, 0.06 s | 32 | |
| `vfx_tracer` | MultiMesh stretched quad, team colour | projectile pool (2,000 / 1,000) | length = speed x 0.02 s |
| `vfx_hit_spark` | GPU, 6 quads, 0.25 s | 32 | scale by damage |
| `vfx_smoke_trail` | **ring-buffer puff MultiMesh** (300 puffs total, one per 0.08 s per damaged ship, life 1.6 s) | 300 | thresholds from `presentation.smoke_hp01` = [0.75, 0.5, 0.25] (R0 C2-31): light grey puffs below 75 % HP, dark below 50 %, black + fire below 25 % (damage-by-smoke readability) |
| `vfx_rocket_flame` + trail | cone mesh + puff pool | shared | |
| `vfx_flak_burst` | dark sphere puff, 25 m radius to match the burst, 0.4 s, plus flash | 16 | |
| `vfx_rail_beam` | stretched additive quad, 0.2 s | 4 | |
| `vfx_bomb_impact_s/l` | flash billboard 0.15 s, fireball GPU (24 / 48 quads) 0.8 s, shock ring mesh 0.4 s, debris, scorch quad | 8 / 3 | l = structure kill |
| `vfx_debris` | MultiMesh, CPU ballistic with analytic gravity (no Jolt, per 01 ADR-06 allowance) | 200 | 3 chunk meshes |
| `vfx_explosion_ship` / `_structure` / `_reactor` | composites of the above; reactor adds a 100 m ring | 6 / 3 / 1 | |
| `vfx_shield_dome` | sphere mesh, fresnel + hex-pattern shader, `TIME` scroll, up to 4 impact ripples in a uniform array; front faces only, **back faces only when the camera is inside the dome** | 8 domes | most players stand inside; keep alpha <= 0.25 on mobile. Also used for the Core's integrated shield (active until `core_shield_until_s`, radius per the Core def, no new VFX id; its countdown is 06's) |
| `vfx_shield_hit` | ripple uniform + spark burst | 8 | |
| `vfx_dock_beam` | additive scrolling cylinder from `HP_Dock` up to the docked ship's tail socket during DOCKED | 8 | three tones for fuel / ammo / repair; hover-descent and touchdown are shown by `vfx_exhaust_cone` plus `vfx_dust_plume` |
| `vfx_pad_lights` | emissive meshes, pulse by state | n/a | no real lights |
| `vfx_build_scaffold` | `build_progress` instance uniform: clip plane rises, hologram lines on the unbuilt part | 60 | |
| `vfx_possess_pulse` | ring pulse and vertical beam at the unit, 0.5 s | 2 | reduced-motion: static ring for 0.3 s |
| `vfx_alert_ring` | world ring at alert location (Commander) | 8 | |
| `vfx_dust_plume` | GPU, 8 quads | 20 | Harvesters within 800 m, and any ship hovering below 15 m above ground or a pad (tail-down landings and launches kick up a radial dust ring) |
| `vfx_ice_steam` | GPU, 6 quads | 10 | Extractors within 800 m |
| `vfx_tether` | stretched cylinder from the Hauler's `HP_Tether` to the towed wreck; the sim link is rigid and kinematic (R0 C3-17: wreck 25 m behind, 8 m below, critically damped), so the **sway is presentation only**: a small damped lateral swing driven by the Hauler's yaw rate | 8 | Hauler |
| `vfx_wreck_smoke` | puff emitter | 10 nearest wrecks only | wrecks otherwise darkened via `wreck` uniform |
| `vfx_spawn_in` | build-style clip reveal | 8 | |

**Pre-warm:** `godot/content/vfx_prewarm.json` lists every VFX id and every material; the loading screen instantiates each once off-screen for two frames (ADR-02: no shader baker on Compatibility). A unit test asserts every `vfx_*` id referenced in any def is in the list.

**Tier scaling** (03 owns the tiers LOW / MEDIUM / HIGH in `quality_tiers.json`; 07 supplies the knobs): HIGH: 2,000 particle quads, sun shadows (800 m, PC only), 4 explosion lights, mesh LOD `threshold_pixels` 1.0 on PC. MEDIUM: 1,000 quads, no shadows, 2 lights, `threshold_pixels` 3.0. LOW: 500 quads, no lights, puff cap 100, exhaust bursts only for the possessed unit, `threshold_pixels` 3.0, 200 individual entity nodes (ART-A1).

---

## 7. UI art direction and iconography

- **Voice:** flat, 2 px strokes, translucent dark panels (`ui_bg_1` at 78 %), corner brackets. No gradients, no skeuomorphism, no red/green status pairs.
- **Markers:** team-shape frame (Section 2.2) with a white class glyph inside, on a `ui_bg_0` plate; allegiance via frame style. 24 px minimum, 32 px on touch.
- **Class glyph rule:** ships = triangle-based glyphs; ground = rectangles with wheels; structures = squares; towers = octagon-based; resources = hex (Ore), droplet (Ice), bolt (Power). Glyphs are drawn on a 32 px grid with a 3 px safe margin.
- **Icons:** SVG sources in `godot/assets/ui/icons/`, rasterised to one atlas (64 px cells, about 1,024 x 512) by `tools/art/build_icon_atlas.py`. Icon ids = `ico_<name>`.
- **Fonts (SIL OFL):** Rajdhani SemiBold for headings, Inter for body and tabular timers; both cover Finnish (a, o with diacritics). Subset to Latin + Latin-Ext with `pyftsubset` (about 60 KB each for web). Minimum size 9 px at 1280x800, target 12 px (R3 s3).
- **Alert design:** every alert = icon shape + short text + unique sound rhythm (Section 8.1); colour is the third channel only.
- **Theme:** `godot/assets/ui/theme_pw.tres` is generated from `palette.json` by `tools/art/build_theme.py` so colours never drift; 06 owns layouts.

---

## 8. Audio

### 8.1 Design and SFX list

**Stylisation (vacuum-appropriate).** Sound cannot travel through vacuum, so the game's explanation is *telemetry*: the possessed unit is heard through its own hull (engine hum, gun thump, cockpit tones), and everything else arrives as clean synthetic "sensor sonification". This permits audible distant explosions without breaking the fiction and keeps the palette synthetic: filtered noise, clean sines, short pulses, sub thumps. No Doppler, no reverb (unavailable in web Sample mode anyway).

**Rules.** Sounds are mono, 22.05 kHz PCM16 WAV, one to two seconds (loops 2-4 s), peak <= -1 dBFS. Loudness targets: loud events -16 LUFS short-term, loops -26 to -23, UI -22. Identity must live in 300 Hz - 4 kHz so phone speakers carry it (checked by spectral centroid in `tools/audio/analyze.py`). Every sound def in `godot/content/defs/sfx.json` (presentation data, excluded from the content hash, R0 C2-34) has: `id`, `files[]` (variations), `bus`, `priority` (0-9), `max_instances`, `cooldown_ms`, `pitch_jitter`, `loop`, `caption` (for 06 subtitles).

| Family | Sound ids (count) | Trigger |
|---|---|---|
| Guns (8) | `gun_dart_fire` x3 variants, `gun_loop_start/loop/end` (burst fire as a loop), `gun_turret_fire`, `gun_hit_hull` x3, `gun_hit_structure` | fire, `HIT` |
| Heavy weapons (9) | `bomb_release`, `bomb_fall_loop` (pitch rises), `bomb_impact_s/l`, `rocket_launch`, `rocket_loop`, `flak_fire`, `flak_burst`, `rail_charge`, `rail_fire` | fire, `BOMB_IMPACT` |
| Destruction (6) | `explode_ship`, `explode_structure_s/l`, `explode_reactor`, `ram_collision`, `wreck_settle` | `DEATH`, `STRUCTURE_LOST` |
| Shield (4) | `shield_up`, `shield_down`, `shield_hit`, `shield_hum_loop` | |
| Flight (12) | `engine_dart_loop`, `engine_heavy_loop`, `engine_scout_loop`, `boost_start`, `boost_loop`, `brake_retro`, `flip_whoosh`, `uplink_fade_static` (loop), `uplink_break`, `touchdown_soft`, `touchdown_hard`, `launch_pad` | `LANDING` (29): `touchdown_soft` for grades AUTO, FAIR, CLEAN, ACE, `touchdown_hard` for HARD, BENT, CRASH; the hover descent is the engine loop pitched by thrust; `LAUNCHED` plays `launch_pad` |
| Docking (6) | `dock_clamp`, `service_fuel_loop`, `service_ammo_loop`, `service_repair_loop`, `service_done`, `undock` | `DOCKED`, `SERVICED`, `LAUNCHED` |
| Ground and structures (12) | `harvester_motor_loop`, `harvester_mine_loop`, `harvester_unload`, `extractor_hum_loop`, `refinery_loop`, `reactor_loop`, `pylon_hum_loop`, `sensor_ping`, `build_start`, `build_loop`, `build_done`, `tether_tension_loop` | |
| Possession (4) | `possess_in`, `release_out`, `handover_request`, `handover_accept` | `POSSESSED`, `RELEASED` |
| UI (11) | `ui_click`, `ui_hover`, `ui_confirm`, `ui_deny`, `place_ok`, `place_invalid`, `queue_add`, `queue_done_ship`, `queue_done_structure`, `unit_cap`, `ui_tab` | |
| Alerts (16) | `alert_core_attack` (4 fast falling pulses), `alert_base_attack` (3 falling pulses), `alert_structure_lost` (low double thud + fall), `alert_harvester_lost` (two-tone fall), `alert_unit_lost`, `alert_low_fuel` (slow single pulse; HUD fuel state, not an `AlertKind`), `alert_low_power` (rising stutter), `alert_bombers` (rising triple, replaces the draft's `alert_scouted`), `alert_core_exposure`, `alert_resource_wait` (two soft equal pulses), `alert_contested` (alternating two-tone), `alert_dusk` (slow descending sweep, moving sun), `alert_info` (one soft blip), `alert_objective`, `alert_chat_ping`, `alert_match_end` | `ALERT` event by `AlertKind`, see the map below; `MATCH_END` |
| Ambience (4) | `amb_cockpit_day`, `amb_cockpit_night` (colder), `amb_base_day`, `amb_base_night` | camera tier + lighting state (`sun_dir`) |

**Alert sounds are keyed by `AlertKind`** (`sim/alert_kind.gd`, R0 Part B.3; ordinals frozen). 06 `alerts.json` stores one sound id per kind; 07 supplies the ids and this default map, and a unit test asserts that every `AlertKind` 0..31 resolves to an existing `sfx.json` id:

| AlertKind | Sound id |
|---|---|
| 0 CORE_UNDER_ATTACK | `alert_core_attack` |
| 1 CORE_EXPOSURE_WARNING, 2 CORE_EXPOSURE, 26 CORE_SHIELD_DOWN | `alert_core_exposure` |
| 3 BASE_UNDER_ATTACK | `alert_base_attack` |
| 4 STRUCTURE_LOST, 21 TOWER_OFFLINE | `alert_structure_lost` |
| 5 LOW_POWER | `alert_low_power` |
| 6 BOMBERS_DETECTED | `alert_bombers` |
| 7 HANDOVER_REQUEST | `handover_request` |
| 8 HARVESTER_ATTACKED | `alert_harvester_lost` |
| 9 UNIT_LOST | `alert_unit_lost` |
| 10 ICE_LOW, 14 PRODUCTION_BLOCKED_CAP, 20 STORAGE_FULL, 22 WAITING_FOR_ICE, 23 WAITING_FOR_ORE, 27 SPEND_LOCKED | `alert_resource_wait` |
| 11 POLE_CONTESTED, 24 RELAY_CONTESTED | `alert_contested` |
| 25 RELAY_CAPTURED | `alert_objective` |
| 12 TEAMMATE_PING, 18 ADJUTANT, 30 SUPPLY_AWAY (SL-5), 31 WING_STATE (SL-2) | `alert_chat_ping` |
| 13 BUILD_DONE, 15 FACTORY_IDLE, 16 PENDING_ORDER, 19 ORDER_OVERRIDDEN, 28 METEOR_WARN (v1.x) | `alert_info` |
| 17 LINK_WEAK | `uplink_fade_static` |
| 29 DUSK_WARN | `alert_dusk` |

Kinds that share a sound differ by priority and by the pitch offset in their `alerts.json` row.

About 92 ids is the ceiling of the table above; v1 targets **78 ids, about 156 files** (variations only for guns, hits, explosions, UI click). **Alerts are information:** each has a unique rhythm and pitch contour so it is identifiable with the eyes closed, plays on the `Alerts` bus (priority 9, never stolen), and Commander-tier alerts pan toward the bearing of the event when panning is supported (Section 8.3).

**Agents cannot listen.** Acceptance is numeric (peak, LUFS, duration, spectral centroid band, DC offset, loop-seam click test) plus one human listening pass per batch of about 40 sounds (owner or hired sound designer, task ART-24/25 sign-off).

### 8.2 Bus layout

| Bus | Parent | Default dB | Contents | Behaviour |
|---|---|---|---|---|
| `Master` | - | 0 | | Limiter on native only (-1 dB ceiling) |
| `Music` | Master | -8 | music | ducked by alerts |
| `SFX_World` | Master | -4 | weapons, engines, impacts | |
| `SFX_Own` | Master | -3 | sounds of the possessed unit | always audible; ducks `SFX_World` by 3 dB while firing |
| `SFX_UI` | Master | -6 | UI clicks, placement | |
| `Alerts` | Master | -2 | sonified alerts | on playback ducks `Music` -6 dB and `SFX_World` -3 dB for 1.2 s |
| `Ambience` | Master | -14 | cockpit/base beds | |
| `Voice` | Master | -4 | reserved (campaign dialogue is text plus synthetic speaker blips in v1; no human voice-over, no voice chat) | |

Ducking is done in code by bus-volume tweens on **all** platforms (one code path), because bus *effects* (sidechain compressor, limiter) do not run in web Sample mode. Per-bus sliders in settings; master mono-down option; captions for every `Alerts` and key `SFX_World` sound (06).

**Voice management:** 32 simultaneous voices on web and mobile, 48 on PC. `AudioEmitter.request(id, pos, priority)` steals the lowest priority, farthest voice. Engines of non-possessed ships are merged: only the nearest 6 play, mixed from three loops by class.

### 8.3 Web Sample-mode constraints and the answers to them

| Constraint (R2 s3.3, confirmed against the 4.7 docs) | Answer |
|---|---|
| No `AudioEffect` on buses in Sample mode | No effect is required for correctness; ducking by volume tweens; any filtering (distance dulling, muffled-in-dome) is baked into variant files |
| No reverb or Doppler | Not used |
| No procedural audio (`AudioStreamGenerator`) | SFX are pre-rendered files from the offline synth (Section 8.4) |
| Positional audio "may not always work" | `AudioEmitter` uses pooled `AudioStreamPlayer3D`; ART-26 spike checks attenuation and panning on Chrome, Firefox, Safari, Android Chrome. Fallback: non-positional `AudioStreamPlayer` with volume computed from distance (no panning) |
| Autoplay requires a user gesture | `app` unlocks audio on first input; 06 owns the click-to-start screen |
| Sample mode decodes whole files into memory | SFX budget <= 5 MB decoded (about 110 s of mono 22.05 kHz); no SFX over 4 s. **Web decoded-audio total <= 15 MB** (5 MB decoded SFX + music/ambience stream buffers; R0 C1-16, replaces 03's 120 MB) |
| Music would be huge as decoded samples | **Music players force `playback_type = STREAM` on web** (accepting higher latency, irrelevant for music); if crackle appears in the single-thread build, the fallback is mono 22 kHz stems shortened to 20 s (ART-26) |
| Initial download <= 20 MB | SFX pack in `core.pck` (about 2.5 MB Brotli, WAV compresses about 50 %); **music is a separate `music.pck` loaded after the menu** (<= 4 MB: mono, 48 kbps Ogg; 03 s11.2 and R6 cite this figure) |

Open verification (ART-26): whether Ogg/QOA SFX play in Sample mode; if yes, SFX can drop to about 1 MB.

### 8.4 Sourcing

| Source | Use | Rules |
|---|---|---|
| **Procedural, ours** (preferred) | all SFX and UI sounds | `tools/audio/sfxgen.py` (numpy only): a sfxr-style synth driven by `tools/audio/recipes/<id>.json`: layers of `{wave: sine|square|saw|noise, f0, f_slope, vibrato, attack, sustain, decay, lowpass, highpass, bitcrush, gain, delay}`; deterministic by seed; writes WAV + metadata. Fully ours, no licence. Haiku agents author and tune recipes using `analyze.py` output |
| Licensed packs | music beds, anything synthesis cannot do | CC0/public domain; purchased commercial licence that allows use in a closed-source game on all our platforms including web; CC-BY only for SFX and music with an entry on the in-game credits page |
| Commissioned | main theme, store trailer | contract assigns or licenses all rights worldwide for all platforms |
| **Forbidden** | | CC-BY-NC, CC-BY-SA and any GPL/LGPL audio (incompatible with a closed commercial release; Triplane audio is GPLv3, R1 s1.4); "free for non-commercial"; anything ripped from games or films; AI-generated audio until the owner decides (Q-ART1); any sample whose licence cannot be proven |

**Licence ledger:** `docs/credits/ASSET_LICENCES.csv` with columns `asset_id, path, sha256, source_url_or_recipe, author, licence, attribution_required, price, date, proof_file`. CI (`tools/check_licences.py`, ART-32) fails if a file under `godot/assets/**` is missing from the ledger or carries a forbidden licence.

### 8.5 Music cues per match phase

Tempo is in beats per minute; every stem of a phase has the same length (64 s, 32 bars at 120) so they stay in sync. Implementation: `AudioStreamSynchronized` per phase (bed + pulse stems) inside an `AudioStreamInteractive` that transitions between phases on bar boundaries (Godot 4.3+ classes; Stream mode on web).

The phase is selected by `SimView.match_arc()` (`MatchArc`: OPEN, EXPAND, SIEGE, OVERTIME), not by wall-clock minutes, because Core Exposure and the hard end are per-mode data (1v1 at 20/30 min, 2v2 25/35, team and others 30/40; R0 C3-19). The minute ranges below are the long-form (team) values; shorter modes use the arc boundaries from `modes.json`.

| Cue | Arc (long-form clock) | Feel | Stems | Layering rule |
|---|---|---|---|---|
| `mus_menu` | menus | expansive, slow, 80 bpm | bed | |
| `mus_open` | OPEN (0-5 min) | quiet tension, sparse pulse, 100 bpm | bed, pulse | pulse fades in when the Chase tier is active |
| `mus_expand` | EXPAND (5-15 min) | rhythmic, building, 110 bpm | bed, pulse | pulse in Chase or when an alert fired in the last 20 s |
| `mus_siege` | SIEGE (15 min to Core Exposure) | heavy, low drones, 120 bpm | bed, pulse | same |
| `mus_overtime` | OVERTIME (Core Exposure to the hard end) | urgent, ticking, 128 bpm | bed, pulse | pulse always on |
| `stg_victory`, `stg_defeat`, `stg_mission_complete` | match/mission end | 4-8 s stingers | single | ducks everything else |

Commander tier lowers `Music` by 3 dB and favours the bed. Campaign missions reuse these cues by id. **Total:** 9 loops + 3 stingers. Web music pack about 3.4 MB; native stereo 128 kbps Ogg about 14 MB.

---

## 9. Map recipe authoring guide

Three v1 maps (`cradle`, `anvil`, `rimewater`), all 8-slot and 8-fold rotationally symmetric about the Z axis so every slot is identical; 1v1 and 2v2 use slot subsets (slots 0 and 2 for 1v1, 0/2/4/6 for four players, `slots_by_player_count` in 02 `modes.json`), and unused slots keep their fields at 50 % yield (01 s5.6). **03 owns the recipe schema** (`tools/schemas/map_recipe.schema.json`, R0 Part B.2), the baker and the validator; this guide is the authoring-level shape on top of it. File: `godot/content/maps/<map_id>/recipe.json`; baked outputs next to it (03 s8.3): `face{0..5}.height.u16`, `face{0..5}.biome.u8`, `face{0..5}.slope.u8`, `face{0..5}.path.u8`, `features.json`, `meta.json`, `preview.png`. 02 owns the `resources` block.

### 9.1 Recipe structure

```json
{ "schema_version": 1, "id": "cradle", "seed": 91027,
  "radius_m": 6000, "face_resolution": 1024, "relief": { "min_m": -500, "max_m": 700 },
  "symmetry": { "rotational": 8, "wedge_start_deg": 22.5 },
  "base_noise": { "octaves": 5, "freq_per_circumference": 6, "amp_m": 90 },
  "regions": [ { "kind": "mare", "lat": 8, "lon": 45, "radius_m": 3200, "floor_m": -320, "edge_m": 600 } ],
  "craters": { "explicit": [ { "lat": 30, "lon": 45, "diam_m": 2400, "depth_m": 280, "rim_m": 220 } ],
               "scatter": { "per_wedge": 60, "diam_m": [60, 600], "power": 2.2 } },
  "rilles": [ { "path": [[10, 30], [22, 45], [28, 60]], "width_m": 160, "depth_m": 70 } ],
  "slots": { "count": 8, "lon0_deg": 22.5, "spacing_deg": 45, "flatten_radius_m": 300, "flatten_edge_m": 150, "flatten_slope_deg": 5, "facing_deg": 0 },
  "poles": { "noon_plateau_radius_m": 1000, "noon_plateau_height_m": 150, "midnight_ice_ring": true },
  "boulder_fields": [ { "lat": -5, "lon": 40, "radius_m": 800, "density": 0.4 } ],
  "biome_rules": "default",
  "resources": { "slot_features": [], "ring_features": [], "pole_features": [], "unused_slot_yield": 0.5 } }
```

(`resources` is filled from the 02 s9.1 template and only tweaked, never invented, in 07's guide; `neutral_structures[]` places the Relay Stations; `rules_overrides` carries the moving-sun settings for campaign maps; `meteor_sets[]` is a reserved v1.x block, 08.) All lengths are metres or degrees, never fractions of `PLANET_RADIUS`; the baker converts. The `symmetry` block means an author edits **one 45-degree wedge** (longitudes **22.5 to 67.5**); the baker replicates it eight times. Bases (slot k) sit on the wedge edges at longitude `22.5 + 45 k` degrees, latitude 0 (the terminator), so no base lies within 10 degrees of a cube edge (R0 C1-09) and the wedge interior holds the contested ground between neighbours.

### 9.2 Authoring steps (a Sonnet or Haiku agent can follow)

1. Copy `content/maps/_template/` to `<map_id>/`; set `id` and a new `seed`.
2. Set `base_noise` for the roughness character (table below).
3. Place `regions` (maria basins first, then highlands) as discs with a floor/height; keep each base slot's 1,500 m neighbourhood clear.
4. Add `craters.explicit` for landmark craters (>= 800 m) and a `scatter` for the rest; place Cold Trap craters (diameter 200-800 m, lat < -5 degrees, depth >= 80 m) explicitly.
5. Add `rilles` as lat/lon polylines.
6. Leave `resources` on the s5.6 template, then add `overrides` for position tweaks only. 02 owns amounts.
7. Add `boulder_fields`.
8. Run `python -I -m moonbake validate content/maps/<id>/recipe.json`, then `bake <recipe> --out content/maps/<id>/` and `preview <recipe> --out content/maps/<id>/preview/`. Read the preview renders (cube-face unfolding of height, slope and biome as PNGs, plus a polar view) and fix every failed check (M1-M12, Section 9.5).
9. Commit recipe and baked faces (LFS).

### 9.3 Biome rules (applied by the baker, first match wins)

| Priority | Condition | Biome |
|---|---|---|
| 1 | inside a resource-node footprint | `cold_trap` or `ore_field` |
| 2 | inside Noon plateau | `solar_plateau` |
| 3 | rille floor | `rille_floor` |
| 4 | crater rim ring (0.88-1.12 x radius) or ejecta ray | `rim_ejecta` |
| 5 | crater floor | `crater_floor` |
| 6 | height < -150 m and slope < 6 degrees | `mare` |
| 7 | height > +250 m or slope > 18 degrees | `highland` |
| 8 | otherwise | `mare` if height < 0 else `highland` |

### 9.4 The three v1 maps

Ids and characters follow 02 (R0 C3-11, Part B.2); display names Cradle / Anvil / Rimewater.

| Parameter | **Cradle** (balanced, ranked default) | **Anvil** (dense cratering, cover and hiding) | **Rimewater** (highlands, ice-rich, leaner Ore) |
|---|---|---|---|
| Character (02) | broad equatorial maria, few large craters, highlands beyond 30 degrees | dense cratering, Ore in crater floors, one rille per slot to its mid-latitude trap | highlands everywhere except a narrow equatorial mare strip; Ore leaner, Ice richer |
| Modes | all | all | all |
| `base_noise` amp | 90 m | 160 m | 130 m |
| Maria / highland / crater-floor share | 45 / 30 / 10 % | 25 / 45 / 15 % | 12 / 65 / 8 % |
| Explicit craters per wedge (>= 800 m) | 3 | 6 | 4 |
| Scatter per wedge | 60 | 110 | 90 |
| Rilles per wedge | 1 short | 1 long (6-10 km), slot to its mid-latitude trap | 1 short |
| Home Ore Fields, home Cold Trap, contested field, mid traps, poles | s5.6 template | template; Ore fields in crater floors; contested field set in a crater bowl | 02 values: mid traps at lat -35 (8,000 Ice / 1.8), Midnight nodes 6,000 / 0.9, leaner Ore fields |
| Boulder fields per wedge | 2 | 4 | 3 |
| Intended deck-flyer cover | moderate | high | moderate-high |
| Campaign use | M1, M2, M3 | M4a, M4b, M6 | M5, M8 (moving-sun rule via `rules_overrides` in M5) |

`glassfield` (huge flat maria, long sight lines) is dropped from v1 and is a v1.x candidate (open question Q-ART8).

### 9.5 Validation checks (`python -I -m moonbake validate <recipe>`; implemented in TA-15, each is a CI test)

M1-M12 are the validate rules of the baker (R0 Part B.2); ART-37 supplies one deliberately failing recipe fixture per check. Checks that depend on layout (M2, M6, M7, M8) run for every slot and, where relevant, for each `slots_by_player_count` layout of `modes.json` (2 players: slots 0 and 2; 4: 0/2/4/6; 8: all).

| # | Check | Pass |
|---|---|---|
| M1 | relief range | within [-500, +700] m |
| M2 | each slot: cells within 600 m | >= 85 % have slope <= 15 degrees and mean slope <= 6 degrees |
| M3 | ore field cells | slope <= 10 degrees |
| M4 | Cold Traps | lat < -5 degrees, floor >= 80 m below rim |
| M5 | symmetry | RMS height difference between rotated wedges <= 8 m |
| M6 | s5.6 distances | home ore 1,000-1,500 m; home trap 1,500-2,000 m south; contested field within 5 % of the midpoint between neighbours |
| M7 | node spacing | >= 150 m between any two resource nodes or from any slot centre except home ones |
| M8 | ground connectivity | A* on the 6 x 256^2 path grid links every Core to its two home fields and home trap (reachable by Harvester), and every Core to the Core of each layout partner (Siege Crawler) |
| M9 | biome coverage | within +-5 percentage points of the map's table row |
| M10 | file size | baked faces <= 4 MB compressed per map (web map pack) |
| M11 | cube edges | no start-slot flatten disc (`flatten_radius_m + flatten_edge_m`) intersects a cube edge; a structure cluster may still straddle an equatorial edge elsewhere, which S-WORLD-1 scene Z8 and TA-19 test |
| M12 | texel step | largest height difference between two edge-adjacent texels of any face <= 200 m (the largest legitimate step is a crater rim on a 128 texel test map, about 90-170 m; real maps at 1,024 texels stay near 100 m). A step this size is already a pillar at chase height; the pre-fix baker produced 378 m single-texel cliffs (craters stamped inside maria were pulled to the pre-mare level), the fixed Cradle bake peaks at about 105 m |

---

## 10. Naming conventions and IP rules

| Item | Convention | Example |
|---|---|---|
| Def id (JSON) | snake_case of the s6 name, assumed from 02 | `dart`, `solar`, `sensor_mast` |
| Asset id | `<prefix>_<def id>`; prefixes `ship`, `gnd`, `str`, `prop`, `proj`, `wreck` | `ship_dart`, `str_sensor_mast` |
| Model file | `godot/assets/models/<ships|ground|structures|props|projectiles>/<asset_id>.glb` | |
| glTF root / parts | PascalCase root; parts `Turret`, `Barrel`, `Roof`, `Arm_L`, `Foundation`, `<PascalId>Far`; hardpoints `HP_*` | `ShipDart` |
| Texture / shader / material | `unit_atlas.png`, `moon_terrain.gdshader`, `unit_lit.tres` | |
| VFX / SFX / music / icons | `vfx_*`, `sfx_*` (file) with def id without prefix, `mus_*`, `stg_*`, `amb_*`, `ico_*` | `vfx_bomb_impact_l` |
| Map | `content/maps/<map_id>/` | `cradle` |
| Recipes | `tools/blender/recipes/<asset_id>.py`, `tools/audio/recipes/<sfx_id>.json` | |
| Variants | suffix `_b`, `_c` | `ship_dart_b` |
| Presentation block in defs | `"presentation": {"mesh": "res://assets/models/ships/ship_dart.glb", "far_mesh_node": "ShipDartFar", "vfx": ["vfx_exhaust_cone"], "sfx": {"fire": "gun_dart_fire"}, "smoke_hp01": [0.75, 0.5, 0.25]}` (R0 Part B.1 lists the full ship `presentation` fields). The key is stripped from every def before the content hash; `sfx.json` and `vfx_prewarm.json` are excluded from it entirely, so art and audio edits never change the hash (R0 C2-34). Display strings are not 07's: they derive as `unit.<id>.name` (06 localisation). | |

**IP rules (binding for all art and audio agents).**
1. No Triplane (or Sopwith-derived) code, art, sound, name, text or data table, and agents never open that source (R1 s1.4).
2. No three-stacked-wing silhouettes; no nation-coloured roundels; the names "Triplane", "Turmoil", "Classic", "Dodekaedron" never appear in files, ids or credits.
3. Ship and structure designs come from the recipe cards above; agents do not take reference images from other games' ships or franchises (no lookalikes of well-known sci-fi craft).
4. No AI-generated final art, icons or audio in v1 (Q-ART2).
5. Fonts SIL OFL only. Earth in the sky is procedural. NASA lunar data may be used as private reference only; the moon is fictional.
6. Every shipped file is in the licence ledger (Section 8.4).

---

## 11. ADR amendment requests

None open. **ART-A1 (visible entity nodes vs the mobile draw-call budget) is accepted** (R0 C1-17, 07 ART-A1): 01 s8.1 and ADR-06 now read "200 individually drawn entity mesh nodes on Reduced, Lite and LOW; farther visible entities draw as `_Far` meshes through per-class MultiMesh pools; the 800 / 400 / Lite caps remain caps on simulated visible entities". Consequences for this doc: Section 5.3 (frame budget) and ART-13 (far-pool tooling); the 03 `EntityViewPool` far-pool path is 03 s10.1/s13 work.

---

## 12. Open questions

| # | Question | Default answer (work proceeds) |
|---|---|---|
| Q-ART1 | Music and audio sourcing: commission a composer, buy a licensed pack, or allow AI-generated audio? | Licensed commercial pack(s) for v1 (budget about EUR 300-800), human audition by the owner; commission a main theme for v1.1; **no AI-generated audio**; SFX are procedural and ours. |
| Q-ART2 | May AI image generators be used for concept boards, store art or UI illustration? | No AI-generated assets in the shipped game; throwaway concept boards allowed, never committed. |
| Q-ART4 | Hero-asset art direction sign-off: who approves the Dart and Core style frames? | The owner reviews three renders of the Dart (Chase, Tactical, **landing pose nose-up on a Pad**) and two of the Core (Chase, Tactical) before the remaining 23 models start (ART-06 gate). |
| Q-ART6 | Cosmetic hull paints in v1 or v1.x? | v1.x; the palette-swap infrastructure exists in v1. |
| Q-ART8 | Is `glassfield` (huge flat maria, long sight lines, bomber-friendly) wanted as a fourth map in v1.x? | Not built in v1; the recipe sketch in the stage-2 draft (`base_noise` 45 m, maria 65 %, no rilles) is kept in git history; decide after launch telemetry on map pick rates. |

Resolved in stage 3 and removed from this table: Q-ART3 (allegiance by frame style, not hue: accepted, R0 C2-21), Q-ART5 (Earth 6 degrees at -Z: fixed by R0 C2-31), Q-ART7 (R = 6,000 m confirmed by the owner, O-1).

---

## 13. Cross-doc dependencies

| Doc | Assumption made here |
|---|---|
| 01 (v1.1) | Section 8.2 asset budgets are ceilings; the 2,048^2 atlas ceiling is refined to 256^2 with headroom; Section 3.4 hull paints are v1.x; s3.1.4 tail-down landing (ships carry `HP_Gear_0..2`); s5.7 slot k at longitude `22.5 + 45 k`; s8.1 200 individual entity nodes on Reduced/Lite/LOW. |
| 02 | Def ids are the snake_case of the 01 s6 names; defs carry the `presentation` block of Section 10 (no `name_key`); 02 owns `footprint_cells` (Section 1.2 gives metres and the 8.68 m divisor), `pad_radius_m` (Core 12, Outpost 10, Pad 10, Hangar 10, Relay Station 12), `smoke_hp01` and the resource amounts; the three v1 maps are `cradle`, `anvil`, `rimewater` with the character and campaign use of Section 9.4; `slots_by_player_count` in `modes.json` drives the layout-dependent validate checks; no `storage_silo`; Siege Crawler and Rail Lance are v1 `core`. |
| 03 | Planet renderer includes `moon_light.gdshaderinc` (with the `sun_dir` uniform) and implements `moon_terrain.gdshader` per Section 3.1; consumes `moon_ramp.png` and `biome_ramps.json`; **owns the recipe schema, the baker, `moonbake validate` (M1-M11 of Section 9.5, TA-15) and the output file names**; implements the `instance uniform` parameters and the far-pool path (ART-A1); provides the quality-tier knobs of Section 6 (`quality_tiers.json`, tiers LOW/MEDIUM/HIGH, TA-31); project setting `rendering/mesh_lod/lod_change/threshold_pixels` per tier; the loading screen runs `vfx_prewarm.json`; `music.pck` <= 4 MB and web decoded audio <= 15 MB (03 s11.2/11.3). |
| 04 | None. Replay and net layers carry only def ids and team index; presentation derives everything else. |
| 05 | Autopilot and SimEvents drive audio/VFX by `SimEvent.Kind` and `AlertKind` only (Section 8.1 triggers). No audio decisions in the sim. |
| 06 | Camera vertical FOV 60 degrees assumed for Section 1.4 (state the real value); markers, allegiance frames (solid/brackets/dashed), shape-coded team badges and captions are implemented in `ui/` from the tokens of Section 2.4 and `ico_*` atlas; `alerts.json` maps every `AlertKind` to a sound id from Section 8.1; the "Relation colours" preset (A11Y-02) reads the `relation` palette variant; audio unlock on first input; settings sliders per bus; reduced-motion switches off pulse effects; the landing gauge label reads "nose from vertical". |
| 08 | New features must add their assets to the inventory with a budget class; SL-5 Supply Canister (v1 stretch, after the scope gate) adds `proj_supply_canister` and `canister_deploy`/`canister_collect` sounds through that rule. |
| CI (ADR-12) | Python available for `tools/art/*`; Blender is optional in CI (nightly rebuild-and-compare job only). `.gitattributes` LFS patterns are by extension (`*.glb`, `*.png`, `*.wav`, `*.ogg`, `*.u16`, `*.u8`) so `assets/_pipeline/*.gd` stays plain text. Art goldens: up to 8 art/night scenes in `golden/art/`, one nightly job (R0 C2-30). |

---

## 14. Work breakdown seeds

IDs are stable. Dependencies name real task IDs of the other docs (TA = 03, UX = 06, GD = 02, NET = 04; `CONTRACT-0` is the R0 contract seed).

| ID | Task | Module / lane | Tier | Depends on | Acceptance criteria |
|---|---|---|---|---|---|
| ART-01 | Look-dev spike S-ART-1: shared `unit_lit` + `moon_light.gdshaderinc` (wrap, radial ambient, earthshine, `sun_dir` uniform), instance uniforms, test sphere, 12 sample meshes, Earth/sun sky | presentation | Opus | TA-25, TA-24 | Golden screenshots on PC, Android-mid, Web-mobile; instance uniforms work on WebGL2 and Adreno or fallback chosen; night mare luminance within 20 % of Section 1.5 targets |
| ART-02 | `palette.json` (incl. the `relation` variant), `build_palette.py`, `tools/art/cvd_check.py` and CI hook | tools | Sonnet | - | Atlas built; all thresholds of Section 2.3 reproduced (within 0.2): team-vs-team CIEDE2000 >= 11.0 under each CVD and >= 20 normal; relation colours >= 20 under CVD; CI fails on a palette change that breaks one |
| ART-03 | Shader library: `unit_lit`, `prop_lit`, `vfx_additive`, `shield_dome`, `hologram_ghost`, include file | presentation | Sonnet | ART-01 | Each compiles on Compatibility (desktop + web); team zones render exact hex at `rgb.r = 1`; emblem offset works for 8 teams; animating `sun_dir` moves the terminator without artefacts |
| ART-04 | Blender helper library `pw.py` (incl. `landing_struts`) and MCP bootstrap | tools | Sonnet | - | Recipes in a fresh file build a test box asset, `finalize()` report matches `validate_glb.py` |
| ART-05 | Import pipeline: `validate_glb.py`, `asset_budgets.json`, `write_import.py`, `post_import_asset.gd`, CI job | tools | Sonnet | ART-04 | A sample glb passes V01-V15; a deliberately bad glb fails each check; V11 requires `HP_Gear_0..2` on ships; post-import converts `HP_*` to `Marker3D` |
| ART-06 | Style frames: `ship_dart` (with tail landing struts) and `str_core` recipes and glb | assets | Opus | ART-03, ART-05 | Pass validator; silhouette test; Dart landing-pose render (nose up on a Pad, three feet on the plane, hover flame down); owner sign-off (Q-ART4) |
| ART-07 | Ships: Lancer, Scout, Bomber, Hauler (each with tail landing struts) | assets | Sonnet | ART-06, TA-30 | Validator green; silhouette test >= 90 %, no mutual confusion; landing-pose acceptance of Section 1.3; team area 6-35 % |
| ART-08 | Ground units: Harvester, Siege Crawler | assets | Sonnet | ART-06 | as ART-07 (minus struts); wheels as separate sub-meshes not required |
| ART-09 | Base core set: Outpost, Pad, Hangar, Shipyard, Vehicle Bay, Refinery | assets | Sonnet | ART-06 | Validator green; foundations present (depth >= 0.6 m); Pad has `HP_Dock`, the painted landing circle (radius `pad_radius_m`) and 12 `HP_Light_*` |
| ART-10 | Simple structures: Pylon, Solar, Reactor, Extractor (Silo removed) | assets | Haiku | ART-06 | Validator green; recipe cards followed (dimension check V08) |
| ART-11 | Towers and support: Sensor Mast, Autocannon, Flak, Missile Tower, Shield Projector, Rail Lance (31 x 39 footprint), Relay Station | assets | Sonnet | ART-06 | Validator green; `Turret`/`Barrel` parts present and pivot at their mounts |
| ART-12 | Wrecks, projectile meshes, 13 props | assets | Haiku | ART-05 | Validator green; props <= 80 tris |
| ART-13 | `<PascalId>Far` meshes and LOD gate for all models; far-pool MultiMesh in the view layer (ART-A1 accepted) | presentation | Opus | ART-07, ART-08, ART-09, ART-11, TA-26 | Silhouette overlap >= 90 % at switch distances; 200 ships + 120 structures render under 400 draws on Android-mid |
| ART-14 | Biome ramps `biome_ramps.json` and `moon_ramp.png` (16 x 64) builder; terrain art tuning with 03 | tools / presentation | Sonnet | ART-01, TA-24 | Rendered biome colours match Section 2.1 within dE00 <= 6 on a flat test scene, day and night |
| ART-15 | Sky shader (stars, sun at `sun_dir`, Earth 6 degrees at -Z above the Midnight Pole) | presentation | Sonnet | ART-01, TA-24 | Earth disc 6 degrees at -Z; no banding; < 0.3 ms on Android-mid |
| ART-16 | VFX set A: muzzle, tracer, hit, rocket, flak, rail, bomb impact, scorch quads, debris MultiMesh | presentation | Sonnet | ART-03, TA-26 | Particle caps respected by a stress test (2,000 quads); frame time delta < 2 ms on PC-mid |
| ART-17 | VFX set B: explosions, smoke puff pool (`smoke_hp01` 0.75/0.5/0.25), shield dome and hit (also the Core integrated shield), dock beam, build scaffold, possession pulse, alert ring, ambient plumes, landing dust, tether sway | presentation | Sonnet | ART-16 | Shield dome inside/outside camera switch works; reduced-motion variants present; hovering ships below 15 m raise `vfx_dust_plume` |
| ART-18 | `vfx_prewarm.json`, loading-screen pre-warm, unit test of id coverage | presentation | Haiku | ART-17, TA-26 | No hitch > 50 ms when each effect first fires (headless log + Android test) |
| ART-19 | Quality-tier knobs (LOD threshold, particle caps, lights, shadows, 200-node cap) wired to the 03 tiers LOW/MEDIUM/HIGH | presentation | Sonnet | ART-16, TA-31 | Three tiers produce stated caps; mobile triangle sum <= 305 k in the Section 5.3 scene |
| ART-20 | UI icon set (class glyphs, shapes, resources, HUD, alerts) and atlas builder | ui assets | Sonnet | ART-02 | 100 icons in one atlas; shape set legible at 16 px; icons referenced by id from 06 |
| ART-21 | Fonts subset and generated `theme_pw.tres` | ui assets | Sonnet | ART-02, UX-12 | Finnish text renders; web font payload <= 150 KB; all theme colours come from `palette.json` |
| ART-22 | Audio synth `sfxgen.py`, recipe schema, `analyze.py` (peak, LUFS, centroid, loop seam) | tools | Sonnet | - | A test recipe renders deterministically; analyzer flags clipping and a bad loop seam |
| ART-23 | SFX recipes batch 1: guns, heavy weapons, destruction, shield | audio | Haiku | ART-22 | 27 ids meet numeric targets; human listening pass signed |
| ART-24 | SFX recipes batch 2: flight, docking, ground/structures, possession, UI, alerts (16), ambience | audio | Haiku | ART-22 | 51 ids meet targets; alerts mutually distinguishable (rhythm test on onset patterns); every `AlertKind` 0..31 resolves to an existing sound id; human pass signed |
| ART-25 | Audio runtime: `AudioEmitter` pool, `default_bus_layout.tres`, code ducking, voice stealing, sfx def loader, `LANDING`-grade touchdown selection | presentation | Sonnet | ART-22 | Bus layout matches Section 8.2; 32-voice cap enforced; priority stealing tested headless |
| ART-26 | Spike S-AUDIO-1: web Sample-mode positional audio, Stream-mode music, Ogg/QOA in Sample mode | presentation | Opus | ART-25, TA-28 | Written result for Chrome, Firefox, Safari, Android Chrome; decision on fallbacks; no crackle over a 10-minute web run; web decoded audio <= 15 MB confirmed |
| ART-27 | Music: source and license (human task, Q-ART1 default) then integrate `AudioStreamInteractive` (phases from `match_arc()`) and stems, `music.pck` | audio | Sonnet | ART-25 | Phase transitions on bar boundaries; `music.pck` <= 4 MB; ledger entries complete |
| ART-28 | Map `cradle` recipe and bake | content | Sonnet | TA-15, CONTRACT-0 | M1-M11 pass for 2-, 4- and 8-player layouts; previews reviewed; 02 `resources` block merged (GD-22) |
| ART-29 | Map `anvil` recipe and bake | content | Sonnet | ART-28 | M1-M11 pass; deck-cover score higher than `cradle` by the preview metric |
| ART-30 | Map `rimewater` recipe and bake (was `glassfield`, replaced per R0 C3-11) | content | Sonnet | ART-28 | M1-M11 pass; highland share 65 % +-5; mid traps at lat -35 |
| ART-31 | (removed: merged into TA-15, R0 C2-02; failing fixtures move to ART-37) | - | - | - | - |
| ART-32 | Licence ledger and `check_licences.py` CI gate | tools | Haiku | - | CI fails on a missing ledger entry or forbidden licence |
| ART-33 | Golden scenes (`golden/art/`, up to 8 scenes in the one nightly golden job): 8 team colours day/night, three tiers, CVD-simulated renders, tail-down landing pose | test | Sonnet | ART-06, ART-14, TA-35 | Up to 8 art goldens committed; CVD renders reviewed; contrast thresholds of Section 2.3 asserted on screenshots |
| ART-34 | Wreck, damage and build-progress shader states plumbed through `EntityViewPool` | presentation | Sonnet | ART-03, TA-26 | `wreck`, `damage01`, `build_progress` change per instance without extra draws |
| ART-35 | Asset QA sweep: silhouette tests, budget report, perf per tier | test | Opus | ART-13 | Report in `perf/`; all assets within budgets; failures filed |
| ART-36 | Mesh LOD gate tool (renders LOD1/2 at switch distance, silhouette IoU) | tools | Sonnet | ART-05 | Tool lists assets under 90 % overlap |
| ART-37 | Map validation fixtures: one failing recipe fixture per check M1-M11 plus a passing recipe, consumed by the TA-15 tests (replaces ART-31's tooling part) | tools | Haiku | TA-15 | Each M-check fails on exactly its fixture and passes on the good recipe |
| ART-38 | Hangar stow presentation: docked-ship node tips horizontal and lowers through the open `Roof` after touchdown, reverse before `LAUNCHED` (sim pose unchanged) | presentation | Sonnet | ART-09, TA-26 | Bomber fits the hall during the stow; no sim read of the stow transform; reduced-motion shows the final pose |

---

## 15. Revision log (stage 3)

Applied on 2026-10-10 against `reviews/R0-resolution-register.md`, owner decisions and 01 v1.1.

| Register ID | Applied in this doc |
|---|---|
| O-1 (R = 6 km) | Header decision 4; Q-ART7 removed; recipe `radius_m` 6000 (9.1) |
| O-2, C1-04(b), C2-10, C3-02 (tail-down landing) | 1.3 landing pose and acceptance; 4.2 `HP_Gear_*`; 4.4 `pw.landing_struts`; 4.5 strut rule on all five ships and pad landing circles; "Docked pose" paragraph (Hangar stow, ART-38); V11; 6 `vfx_dock_beam`/`vfx_dust_plume`; 8.1 touchdown by `LANDING` grade; ART-06/07/09 and Q-ART4 (Dart landing-pose frame) |
| O-4, C3-14 (Silo cut; Crawler and Rail Lance stay) | Scale chart, silhouette table, recipe cards and 5.1 inventory (`str_silo` removed); ART-10; Crawler "cut candidate" label dropped; Rail Lance footprint 31 x 39 (4 x 5 cells); hours recomputed |
| O-5, C1-09 (slots at lon `22.5 + 45 k`) | 9 intro, 9.1 (wedge lon 22.5-67.5), 9.5 layout note and M11 |
| C1-10 (g, h) | `moon_terrain.gdshader` and `moon_light.gdshaderinc` names confirmed (1.5, 3.1); map CLI and output names per 03 (9 intro, 9.2) |
| C2-02, C3-11 (map ids, schema, M1-M11 as validate rules) | 9 intro, 9.1 recipe example in 03's schema, 9.2 CLI, 9.4 map table (`cradle`, `anvil`, `rimewater`; glassfield to Q-ART8), 9.5; ART-28..30; ART-31 removed (merged into TA-15) and ART-37 added; 13 |
| C2-03 (enums, alert sounds keyed by `AlertKind`) | 8.1 Alerts family (16 ids) and the AlertKind-to-sound map; ART-24 coverage test |
| C2-21 (07 owns colour; Relation-colours variant) | 2.2 `relation` variant; 2.3 thresholds; ART-02 |
| C1-11 (CVD thresholds 11.0 / 20) | 2.3 results table; ART-02 |
| C1-16, C2-32 (audio sizes; two OFL families) | 8.3 `music.pck` <= 4 MB, web decoded audio <= 15 MB; 7 fonts unchanged (two OFL families confirmed) |
| C1-17, ART-A1 (200 nodes + far pools) | 5.3, 11 (accepted, no open amendment), 6 tier scaling, ART-13/19 |
| C2-26 (seed merge table, real dependency IDs) | 14 seed table rewritten with TA/UX/CONTRACT-0 IDs; ART-31 merged into TA-15 |
| C2-29 (tier names; threshold_pixels; shadow distance) | 1.5 shadows row, 6 tier scaling |
| C2-30 (golden set) | ART-33 (up to 8 art scenes, one nightly job); 13 |
| C2-31 (smoke 0.75/0.5/0.25; foundation; Earth; atlas 256^2; divisor 8.68 m) | 6 `vfx_smoke_trail`; 4.2 Foundation (min 0.6 m); 3.1; 1.5 sky; 4.3 unchanged at 256^2; 1.2 divisor; 10 `smoke_hp01` |
| C2-34 (content hash inputs) | Header decision 6; 8.1 `sfx.json`; 10 presentation row |
| C3-17 (kinematic tether) | 6 `vfx_tether` (sway presentation only) |
| C3-05 (Core integrated shield) | 4.5 Core card; 6 `vfx_shield_dome` reuse |
| C3-19 (per-mode exposure timers) | 8.5 music phases selected by `match_arc()` |
| O-4 (moving sun stays) | Header decision 5; 1.5 `sun_dir` uniform; `alert_dusk` (DUSK_WARN); 9.4 M5 map note |
| R0 B.11 A-57, A-58 (CONTRACT-0 amendments 04, 2026-10-14; ART-01 REPORT s6) | 1.5 include path `godot/src/presentation/shaders/moon_light.gdshaderinc`, Compatibility sRGB note (`ml_to_linear` / `ml_encode`), earthshine gain 0.50, rim faded in by camera height 1.5-4.5 km (HUM-09 taste check); 4.3 instance-uniform fallback chosen: `UnitMaterialCache` 8 x 5 materials, `unit_lit_instanced` kept for v1.x; `presentation/MODULE.md` is the contract for views, pools, VFX and the material cache (planet keeps its own) |
