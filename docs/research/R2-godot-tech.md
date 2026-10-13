# R2 - Godot Technology Research (state as of 2026-10-09)

Scope: what the current Godot engine can and cannot do for a 3D, spherical-moon, RTS-plus-flight game that must ship to PC, Android, iOS and the browser, with internet multiplayer and AI-agent-driven development.

Confidence tags used throughout:

- **[V]** verified against a primary source read during this research (official docs at the `4.7` branch, Godot source at tag `4.7-stable` or `master`, GitHub API, release notes).
- **[S]** secondary source (blog, forum, vendor page, search summary). Treat as indicative.
- **[U]** unverified inference or recommendation of this report. Needs a spike before it becomes a project decision.

Source IDs such as `[D-web]` point to the "Sources" list at the end. Godot source paths are relative to `github.com/godotengine/godot` at the stated tag.

---

## 0. TL;DR (ten decisions the plan can lean on)

1. **Engine version:** pin **Godot 4.7.2-stable** (released 2026-08-18). 4.8 hit feature freeze on 2026-09-29 (dev7); do not adopt it before 4.8.1. [V]
2. **Web = Compatibility renderer only (WebGL2), wasm32, no WebGPU upstream.** So the game must be art-directed to look right on the Compatibility renderer everywhere; Forward+/Mobile are optional native-only upgrades. [V]
3. **No C#.** C# still cannot export to Web in 4.7.2 or 4.8-dev7, Android/iOS C# is still "experimental", and 4.8 jumps the .NET floor from 8 to 10. Use **typed GDScript** + optional **GDExtension** (godot-cpp 10 or gdext) for native-only hot paths. [V]
4. **One server can serve ENet, WebSocket and WebRTC clients at once only if we write our own thin packet layer.** The built-in `SceneMultiplayer` takes exactly one peer. API surface for the workaround exists (`MultiplayerPeer.poll/get_packet/put_packet`, `SceneMultiplayer.send_bytes`). [V for API, U for end-to-end]
5. **Spherical gravity is easy** (`Area3D.gravity_point`, `CharacterBody3D.MOTION_MODE_FLOATING`, `RigidBody3D.custom_integrator`), but for hundreds of ships we should plan a **custom arcade integrator** and use Godot physics only for queries and static colliders. [V for APIs, U for plan]
6. **Precision:** single precision is fine for a moon radius up to roughly 8 km without tricks (official third-person limit), acceptable to ~32 km (1-2 mm steps), and borderline at 50 km (4 mm steps) where camera-relative rendering is needed (official table). **Do not use `precision=double`**: no official templates, and the 4.7 CI only builds it for a Linux editor. [V]
7. **NavigationServer3D cannot path across a whole sphere**: the map has one global `up` vector that the funnel algorithm uses. Use **AStar3D on a geodesic grid** for ground units. [V from source]
8. **Planet terrain is DIY.** No maintained, standard-template-compatible spherical terrain addon exists; best reference is a GDScript cube-sphere chunked-LOD project. Compute shaders do not exist in Compatibility, so generate on CPU or by vertex shader. [V/S]
9. **Hosting landscape changed in 2026:** Hathora shut down 2026-05-05, Unity Multiplay support ended 2026-03-31. Use a plain Linux VPS, Edgegap, Gameye, GameFabric (Agones) or self-run Agones; Nakama for accounts/matchmaking. [S, several vendor and third-party sources agree]
10. **Agent tooling is good enough:** `godot --headless` runs scripts, physics and networking without a GPU; GUT 9.7.1 and gdUnit4 6.2.2 both support 4.7; set GDScript typing warnings to Error; screenshots need Xvfb plus Mesa software drivers. `gdtoolkit` is stale (last release 2025-10-09). [V]

---

## 1. Versions, release dates, support policy

### 1.1 Release table [V: GitHub releases API, `[D-gh-rel]`; godotengine.org blog `[D-blog]`]

| Version | Date | Notes |
|---|---|---|
| 4.8-dev7 | 2026-09-29 | **Feature freeze announced.** No beta/RC listed yet. Docs table says 4.8 stable "Q4 2026 (estimate)". |
| 4.7.2-stable | 2026-08-18 | Current stable. 57 fixes (39 contributors), includes a MultiplayerSpawner fix (GH-109864). |
| 4.7.1-stable | 2026-07-14 | 78 fixes. |
| 4.7-stable | 2026-06-18 | "Lights, Camera, Action!" |
| 4.6.3-stable | 2026-05-20 | Last 4.6 patch seen. |
| 4.6-stable | 2026-01-26 | Jolt becomes default for new 3D projects. |
| 4.5.2-stable | 2026-03-19 | 4.5 branch (partial support). |
| 4.5-stable | 2025-09-15 | |
| 4.4-stable | 2025-03-03 | Jolt integrated (experimental), Metal backend. |
| 4.3-stable | 2024-08-15 | Single-threaded web export. |

(Third-party sites sometimes say 4.7 shipped on June 19; the GitHub release and the official blog both say 2026-06-18.)

### 1.2 Support policy [V: `[D-policy]`]

- Table in the docs (2026): **4.7 full support, 4.6 full support, 4.5 partial (security and platform fixes only), 4.4 and older end of life.**
- Rule: a stable branch is supported at least until the next stable branch has its first patch release; only the latest patch of each minor series is supported.
- Patch releases are "safe and strongly recommended"; minor upgrades "may include breaking changes and regressions" and must be tested.

**Implication:** start on 4.7.2, accept 4.7.x patches automatically, and treat the move to 4.8 as a planned task that starts at **4.8.1** (expected roughly Dec 2026 to Jan 2027, [U]).

### 1.3 What 4.8 (master) is bringing so far [V: dev snapshot posts `[D-dev2]`, `[D-dev4]`, `[D-dev5]`, `[D-dev7]`; source diff]

Relevant to us:

- **.NET floor jumps from net8.0/C# 12 (4.7) to net10.0/C# 14 (master)** (read from `GodotSharp.csproj` at both refs). Another reason to avoid C#.
- Jolt updated **5.5.0 -> 5.6.0**; mbedTLS 3.6.5 -> 4.1.1; Emscripten bumped to **6.0.1** (GH-122412); ENet stays 1.3.18; Recast stays 1.6.0.
- **Decals now work in the Compatibility renderer** (GH-118070): soft cap 64 decals per frame (project setting), hard limit 8 per surface. Useful for crater and scorch marks.
- Mip-level **texture streaming** (GH-113429), non-allocating physics queries (GH-113970), `Object` property access ~1.6x faster (GH-122596).
- Android: `AndroidSDKManager` (GH-121849) automates SDK/JDK setup; AccessKit screen reader on Android and iOS; touch support in `TabBar`/`PopupMenu`.
- **Not coming:** no WebGPU, no C# web export, no navigation or multiplayer headline changes. **wasm64 was reverted** (see 3.4).

### 1.4 Upstream contribution policy [V: `[D-policy]`]

The Godot Foundation (2026-06-30) prohibits autonomous AI agents and AI-written issue/PR text in the Godot repositories (bans possible). **Our agents must never file upstream issues or PRs**; a human must write and submit them. A headless-stall report (#122707) was closed purely because it was AI-written, so its claim is unverified (see 10.6).

---

## 2. Renderers

### 2.1 Overview [V: `[D-render]`, `[D-sysreq]`]

| | Compatibility | Mobile | Forward+ |
|---|---|---|---|
| Graphics API | OpenGL (ES 3.0 / GL 3.3; WebGL2 on web) | RenderingDevice: Vulkan, D3D12, Metal | RenderingDevice: Vulkan, D3D12, Metal |
| **Web** | **Yes (only option)** | No | No |
| **Android** | Yes, Android 7.0+, GLES 3.0 | Yes, Android 9.0+, Vulkan 1.0 | Supported but "poorly optimized" |
| **iOS** | Yes (GLES 3.0; the only renderer in the iOS simulator) | Yes, iOS 16 (Metal) / iOS 15 (Vulkan) | same |
| Desktop | Yes (GL 3.3 / D3D11) | Yes | Yes (default) |
| Performance | Lowest fixed cost, cost climbs fast with scene complexity | Medium | Highest base cost, low scaling cost |

Rules from 4.4 onward: if Vulkan is missing the RD renderers fall back to D3D12 (and vice versa), then to Compatibility ("Fallback to OpenGL 3" project setting). [V]

### 2.2 Feature gaps that matter for this game [V: `[D-render]`, `[D-lod]`, `[D-occ]`, `[D-mm]`, `[D-vis]`]

| Need | Compatibility (web/low-end) | Mobile / Forward+ | Note |
|---|---|---|---|
| Custom shaders (spatial, canvas_item, particles, sky) | Yes | Yes | Fine for planet, shields, lasers. Screen/depth texture available everywhere. Normal-roughness buffer is Forward+ only. |
| **Compute shaders** | **No** | Mobile: yes but slow on older devices; Forward+: yes | No GPU terrain/flow-field generation on web. |
| MultiMesh | Yes | Yes | No per-instance culling (all-or-none): split into regional MultiMeshes. |
| GPU particles | Yes, **no trails, no SDF collision** | Yes | Fine for exhaust/explosions. |
| Mesh LOD | Yes (auto-generated at import, screen-space threshold, default 1 px) | Yes | Not auto for raw OBJ; use glTF/GLB. |
| Visibility ranges ("HLOD") | Yes | Yes | Manual LOD and fading for structures. |
| Occlusion culling | CPU rasterizer, all renderers | same | Mostly useful indoors; for a planet we need our own **horizon culling**. |
| Shadows | Yes; shadowed lights use multi-pass; 8 omni + 8 spot per mesh; no PCSS; no light projectors | Mobile: 256 lights per view | Keep to 1 directional sun plus few local lights. |
| Decals | **Not in 4.7; yes in 4.8 dev** | Yes | |
| Depth buffer | **24-bit, no reverse-Z** | 24-bit reverse-Z (Mobile), 32-bit reverse-Z (F+) | Planet-scale view distances will z-fight in Compatibility: adapt near/far with altitude or split cameras. [U for the mitigation] |
| Color | RGBA8 (LDR) | RGB10A2 / RGBA16F | Glow supported everywhere; SSR, volumetric fog, SDFGI, VoxelGI, DoF are not in Compatibility. HDR output not in Compatibility. |
| 3D resolution scaling | `scaling_3d_scale` bilinear/nearest supported | + FSR1/FSR2/MetalFX | FSR1 in Compatibility not verified [U]. |

### 2.3 WebGPU status [V/S]

- Upstream docs (4.7 and master): "Godot currently does not support WebGPU, which is a prerequisite for allowing Forward+/Mobile to run on the web." Proposal `godot-proposals#6646` is still open (comments as late as 2026-07-01). [V]
- At least four community forks exist; the most visible (`dwalter/godotwebgpu`, based on 4.6.2, public beta May 2026) is self-reported and not upstream. A maintainer-level comment says merging anything upstream "is going to take many many months". [S]
- **Plan on WebGL2/Compatibility for the lifetime of this project.** WebTransport (the UDP-like browser transport) is also only a proposal (`godot-proposals#3899`, open). [V]

---

## 3. Web export

### 3.1 Requirements and modes [V: docs 4.7 `[D-web]`, `platform/web/export/export_plugin.cpp` at 4.7-stable]

- Browser needs WebAssembly + WebGL 2.0. Docs recommend Chromium or Firefox; "Safari has several issues with WebGL 2.0 that other browsers don't".
- **Single-threaded export (since 4.3) is the default and preferred**: no special headers, works on itch.io, Poki, CrazyGames, and works on macOS/iOS Safari. Multi-threaded needs `SharedArrayBuffer`, i.e. a secure context plus `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`; without them "the project will not run". A PWA option installs a service worker that simulates the headers (secure context still required).
- Export options (defaults): `variant/thread_support=false`, `variant/extensions_support=false`. Template variants combine release/debug, with/without GDExtension ("dlink") and with/without threads (`_nothreads`). Feature tags exposed: `threads`/`nothreads`, `web_extensions`/`web_noextensions`, `wasm32`.
- **GDExtension on web:** needs "Extensions Support" and extensions compiled for web, and "like thread support" requires cross-origin isolation headers. Consequence: a native extension on web forfeits the easy single-thread hosting story.
- Pausing: the browser pauses `_process`/`_physics_process` in background **tabs** (not windows), which "can cause networked games to disconnect". Netcode needs long timeouts plus reconnect/resume.
- `user://` needs IndexedDB/cookies enabled; private mode breaks persistence. Fullscreen and pointer-lock must start inside an input-event callback. Gamepads appear only after a button press.

### 3.2 Size [S + V]

- Official 4.3 article: web `.wasm` about **40 MB raw / about 5 MB Brotli**. [V: `[D-web43]`] The docs say gzip gives roughly a quarter; Brotli precompression recommended.
- Custom templates (3D kept, features trimmed): community reports 16-20 MB raw, 2.7-5 MB compressed. [S] 4.7 numbers were not measured (see Uncertainties).
- Hosts: GitHub Pages compresses on the fly (gzip); itch.io and GitLab Pages do not. [V]

### 3.3 Audio, input, memory [V]

- Default web audio is **Sample playback via Web Audio API** (low latency even single-threaded) but with no AudioEffects, no reverb/doppler, no procedural audio; positional audio "may not always work correctly". Stream mode restores everything with higher latency (especially without threads).
- Autoplay restrictions: require a click/tap/key before audio.
- Memory: the web target is **wasm32**. A `memory64` flag existed (GH-102378 merged 2026-02-26 in the 4.7 cycle), but it was **reverted on master on 2026-08-18 (GH-122538)** because the produced wasm64 binaries "are not usable". Claims on the web that "4.7 added wasm64 web exports" are wrong. [V]
- Official RAM figures for web exports: minimum 2 GB (mobile) / 4 GB (desktop); recommended 4 GB (mobile) / 8 GB (desktop). [V: `[D-sysreq]`]

### 3.4 Networking limits [V]

Web supports only HTTP client/request, **WebSocket (client only)** and **WebRTC**. No raw TCP/UDP, no ENet. HTTP classes have extra restrictions. A page served over HTTPS must use `wss://`.

### 3.5 Physics, threads and generation on web [V/U]

- The built-in Jolt module is compiled for web (`modules/jolt_physics/config.py` has no platform exclusion; `SCsub` adds WASM-SIMD flags; the "run physics on a separate thread" path is `#ifdef THREADS_ENABLED`). Old anecdotes that "Jolt does not work on web" concern the earlier GDExtension. **Runtime behavior of Jolt in single-thread web is untested by us.** [V build, U runtime]
- In single-threaded builds there are no worker threads, so `WorkerThreadPool`-based terrain generation will not run in parallel. Budget generation per frame. [U]

---

## 4. Language choice: GDScript vs C# vs GDExtension

### 4.1 Support matrix [V: `[D-csharp]`, `[D-and]`, `[D-ios]`, source, `[D-gh-cpp]`, `[D-gdext-web]`]

| | Web | Android | iOS | PC | Notes |
|---|---|---|---|---|---|
| **GDScript** | Yes | Yes | Yes | Yes | One code path everywhere. |
| **C# (.NET)** | **No** ("Godot 4 currently cannot be exported to the web") | Experimental | Experimental; **macOS host required**; simulator x64 templates only | Yes | .NET 8 in 4.7, **.NET 10 in 4.8**. Official web PR `#106125` is still open and unmerged (milestone "4.x"); several rewrites were closed. |
| **GDExtension, C++ (godot-cpp 10.0.0-stable, 2026-09-15)** | Yes with the dlink template, matching Emscripten, and cross-origin isolation | Yes (16 KB page alignment needed, NDK r28 default) | Yes | Yes | v10 is versioned independently of Godot; `api_version=4.3` builds work on all later 4.x. |
| **GDExtension, Rust (gdext 0.5.5, 2026-08-09)** | **Experimental**: nightly Rust, `-Zbuild-std`, `wasm32-unknown-emscripten`, panics abort the game; Rust 1.93+ needs `-Z emscripten-wasm-eh=false` | Yes | Yes | Yes | Reasonable server-side or native-only accelerator, painful on web. |

C# on web is also tracked as a proposal (`godot/#70796`) with prototypes shown at GodotCon Boston; there is **no merged implementation and no date**. [V/S]

### 4.2 Typed GDScript performance [V official statement + S anecdotes]

- Official: typed GDScript "improves performance by using optimized opcodes when operand/argument types are known at compile time"; JIT/AOT is "planned" but not present. [V]
- Anecdotal community numbers put native C++ at roughly 10-100x faster than GDScript in tight numeric loops; C# is several times faster than GDScript but pays marshalling cost at the engine boundary. [S, no 2026 benchmark found]
- Practical rules for a sim with hundreds of units: keep authoritative sim state in packed arrays (`PackedFloat32Array`, `PackedInt32Array`, `PackedVector3Array`), not one `Node` per unit; use bulk built-ins; use `MultiMesh` for projectiles/debris; never call across the script boundary per entity per frame. [U]

### 4.3 Enforce typing mechanically [V: `ProjectSettings` class reference at 4.7-stable]

Set these in `project.godot` to **Error (2)**: `debug/gdscript/warnings/untyped_declaration`, `inferred_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument`, `unsafe_cast`, `unsafe_void_return`, `return_value_discarded`, `missing_await`, `unused_variable`, `unused_parameter`, `shadowed_variable`, `integer_division`, `narrowing_conversion`. This turns "agent wrote untyped code" into a failing `--headless` run and is more reliable than any external linter.

---

## 5. Multiplayer

### 5.1 Building blocks [V: `[D-mp]`, class references at 4.7-stable]

- `MultiplayerAPI` / `SceneMultiplayer` (RPC + replication + optional auth handshake) on top of one `MultiplayerPeer`.
- Peers: `ENetMultiplayerPeer` (UDP, ENet 1.3.18, reliable/unreliable/ordered channels), `WebSocketMultiplayerPeer` (TCP; client works on web, server only native), `WebRTCMultiplayerPeer` (star or mesh).
- Replication: `MultiplayerSpawner`, `MultiplayerSynchronizer` (`replication_interval`, `delta_interval`, `public_visibility`, per-peer `set_visibility_for`, `add_visibility_filter(Callable)`, modes Always / On Change / Never). `SceneMultiplayer` defaults: `max_sync_packet_size=1350`, `max_delta_packet_size=65535`, `auth_timeout=3.0 s`, `server_relay=true`, `allow_object_decoding=false`.
- Raw packets: `SceneMultiplayer.send_bytes(bytes, id, mode, channel)` + `peer_packet` signal; or drive any `MultiplayerPeer` directly (`poll()`, `get_packet()`, `put_packet()`, `set_target_peer()`, `transfer_mode` = unreliable 0 / unreliable_ordered 1 / reliable 2).
- Handshake: `auth_callback`, `send_auth()`, `complete_auth()`, `peer_authentication_failed`.

### 5.2 Transport matrix

| | Native client (Win/Mac/Linux/Android/iOS) | Web client | Server on Linux | Reliability model | Extra infrastructure |
|---|---|---|---|---|---|
| **ENet** | Yes | **No** | Yes, UDP port | reliable + unreliable channels | none (open UDP port) |
| **WebSocket** | Yes | Yes (client) | Yes; TLS via `TLSOptions.server()` or a reverse proxy | **TCP only**: head-of-line blocking | `wss://` cert/hostname for HTTPS-hosted web builds |
| **WebRTC** | Needs `webrtc-native` GDExtension | **Built in** | Needs `webrtc-native`; `create_server()` exists (peer id 1, relay enabled) | SCTP data channels: **unreliable and unordered supported** | Signaling service (WebSocket/HTTP) + STUN; TURN for hostile NATs |

`webrtc-native` **1.2.2-stable (2026-09-30)**: libdatachannel 0.24.6, mbedTLS 3.6.7, GDExtension for Godot 4.3+, buildable for windows, linux, osx, android, ios. [V: GitHub releases/README] The Godot WebRTC tutorial page carries an "article outdated" flag; trust the class reference.

### 5.3 Can ONE dedicated server serve native and web clients?

- **Out of the box: no.** A `MultiplayerAPI` has exactly one `multiplayer_peer`. Splitting the scene tree into several `MultiplayerAPI` instances (via `root_path`) partitions nodes; it does not bridge transports. [V]
- **Simplest valid options:**
  1. All clients (native too) use **WebSocket** over TLS. Works everywhere, costs TCP latency for everyone. Used by at least one open-source Godot space game that lets native clients join web sessions. [S]
  2. All clients use **WebRTC** (built in on web, `webrtc-native` elsewhere): one transport with unreliable delivery on every platform; costs signaling + STUN/TURN. A bonus: DTLS fingerprints are exchanged via signaling, so no CA-signed certificate per dynamically allocated server IP. [U, general WebRTC knowledge]
- **Recommended for this project [U, needs spike S-NET-1]:** a *thin transport-agnostic game protocol* in our own code. The server process instantiates up to three listeners (`ENetMultiplayerPeer`, `WebSocketMultiplayerPeer`, `WebRTCMultiplayerPeer`), `poll()`s them each tick, wraps each connection as `Connection{id, transport, rtt}`, and sends/receives our own `PackedByteArray` messages. Control plane (lobby, orders) = reliable messages; state plane = unreliable snapshots. Native clients use ENet, browsers WebSocket first (WebRTC later as an optimization). Peer-id collisions between listeners are handled by our own connection ids.

### 5.4 Scaling with hundreds of entities

- No official benchmarks exist for `MultiplayerSynchronizer` at scale; community numbers are anecdotal (one Godot-hosting vendor reports stability issues around 40 CCU/server; unverified). [S]
- Known design properties [V from source/docs]: delta sync exists for On Change mode (`_send_delta`, bounded by `max_delta_packet_size`); values go through generic `Variant` encode/compress (no quantization, no priority/relevancy, **no interpolation, prediction or lag compensation**; proposals for these are open, e.g. `godot-proposals#7280`); a `Callable` visibility filter runs per peer per synchronizer; one `Node` + one synchronizer per entity makes CPU cost grow linearly in nodes. Synchronizers cannot replicate `Object` properties.
- **Workaround to plan for from day one [U]:**
  - Authoritative sim in packed arrays; server tick 20-30 Hz; state packets built by hand into `PackedByteArray` and kept **below ~1200 bytes** (per ENet mailing-list discussion, fragmented unreliable packets get promoted to reliable [S]; Godot's own sync packet default is 1350).
  - **Interest management** by spatial cell on the sphere (e.g. icosphere cell id): each client gets only entities in its camera/commander region plus a coarse far layer.
  - **Quantization:** position as 3x u16 relative to a cell origin, orientation as smallest-three (4 bytes), velocity as 3x i8, hp/flags as u8; sketch of ~16 bytes full, 4-8 bytes delta per entity. Target <= 20-30 KB/s per client.
  - Delta against the last acked snapshot, periodic reliable keyframe, orders/spawns/deaths reliable.
  - Client: snapshot interpolation 100-150 ms behind, local prediction only for the directly controlled unit.
- 4.7.2 fixed "peers stop replicating when a spawner-spawned node is deleted" (GH-109864): another reason to stay on >= 4.7.2 if we use spawners at all. [V]
- Optional reference: `foxssake/netfox` (rollback/interpolation addon, v1.35.3 from 2025-11-23; Edgegap's Godot sample "Forest Brawl" uses it). Aimed at small-scale action games, not hundreds of RTS units. [S]

### 5.5 Dedicated server build [V: `[D-ded]`]

- No special binary: run any export template or editor with `--headless` (sets headless display + Dummy audio).
- Export preset mode **"Export as dedicated server"** strips textures/materials (placeholders) and adds feature tag `dedicated_server`; check with `OS.has_feature("dedicated_server")` or `DisplayServer.get_name() == "headless"`.
- Run under systemd (`flush_stdout_on_print` setting) or Docker (`debian:bookworm-slim`, UDP port mapping). Keep server and client builds on the **same engine version and precision**.

---

## 6. Physics

### 6.1 Jolt [V: `[D-jolt]`, source]

- Jolt arrived as built-in in **4.4 (experimental)** and is the **default for new 3D projects since 4.6**; existing projects keep their setting. Set `physics/3d/physics_engine="Jolt Physics"` explicitly in our `project.godot`.
- Bundled Jolt: **5.5.0 in 4.7**, 5.6.0 on 4.8 master. The old `godot-jolt` extension (v0.16.0, 2026-02-14) is "maintenance mode" and not needed.
- Differences: joint soft-limit properties unsupported, margin handling differs, kinematic body contacts opt-in, `PhysicsServer3D` thread safety "experimental". Compiled with `JPH_DOUBLE_PRECISION` when `precision=double`.
- No authoritative mobile/web performance numbers found. Jolt is built with SIMD paths for ARM and WASM. Measure early (spike S-PHYS-1). [U]

### 6.2 Spherical gravity [V: class references 4.7-stable]

- `Area3D`: `gravity_point = true`, `gravity_point_center`, `gravity` (surface value), `gravity_point_unit_distance` (distance at which strength equals `gravity`; **inverse-square falloff** when > 0), `gravity_space_override = Replace`. Place one large Area3D at the moon centre.
- `CharacterBody3D`: `up_direction` can be changed every frame to `(pos - centre).normalized()`; `MOTION_MODE_FLOATING` "is suitable for games without ground like space games".
- `RigidBody3D`: `custom_integrator` + `_integrate_forces()` for fully custom gravity/thrust.
- 3D physics interpolation exists in the SceneTree (4.4/4.5+) for smooth rendering when physics ticks (e.g. 30 Hz on mobile) differ from display rate.

### 6.3 Recommendation for this game [U]

Ships and projectiles should be driven by our own deterministic arcade integrator (position, velocity, orientation basis, planet-centre gravity, altitude soft ceiling) in packed arrays. Use Godot physics for: static structure/terrain colliders for ground-level collisions, ray/shape queries (4.8's non-allocating query results help), and `Area3D` overlap triggers. Terrain collision for ships can be an analytic height lookup (`height(dir)`), not a mesh collider; Godot's `HeightMapShape3D` is planar.

---

## 7. Large worlds and precision

### 7.1 Official guidance [V: `[D-lwc]`]

Float32 step sizes: [4096,8192) = 0.0005 m (recommended maximum for **third-person** 3D); [8192,16384) = 0.001; [16384,32768) = 0.0019 (recommended maximum for **top-down**); [32768,65536) = 0.0039 (maximum recommended for **any** 3D game; "double precision is usually required past this point"). GDScript `float` is already 64-bit; only `Vector2/3/4` are 32-bit.

For a moon centred on the origin, surface-level objects sit at distance R from the origin:

| Radius R | Step at surface | Verdict |
|---|---|---|
| 5 km | 0.5 mm | fine |
| 8 km | 0.5 mm | fine (third-person limit) |
| 10 km | 1 mm | fine |
| 20 km | 1.9 mm | fine for ships/structures; watch tiny debris and thin beams |
| 32 km | 1.9 mm (just under the 32,768 m boundary) | acceptable; the official ceiling for top-down games |
| 50 km | 3.9 mm | borderline (official ceiling for "any 3D game"); use camera-relative rendering |

### 7.2 Double-precision builds: avoid [V]

- Needs `precision=double` for the editor and **every** export template; outputs get a `.double` suffix; **GDExtensions must be rebuilt** (`REAL_T_IS_DOUBLE`); server and clients must run the same build type.
- No official templates. In 4.7-stable CI, `precision=double` appears only in one Linux editor+sanitizers job (`.github/workflows/linux_builds.yml`); Android/iOS/Web/Windows/macOS workflows do not build it.
- Docs: "may not perform well on low-end mobile devices"; triplanar mapping and non-local GPUParticles3D do not benefit.

### 7.3 Recommended practice [U, consistent with the docs]

1. Choose a **moon radius of 10-20 km** as the baseline; make `PLANET_RADIUS` a single constant and test 8, 20, 32 km in a spike.
2. Keep **authoritative world state planet-centred in float64** (GDScript floats / `PackedFloat64Array`, or fixed-point ints) and send quantized local offsets over the network.
3. Render in **camera-relative space** if R > ~20 km: a `WorldRoot` node holds all visual nodes and is re-based when the camera has moved ~1 km; terrain chunks use chunk-local vertices with a per-chunk origin. Docs warn origin shifting "introduces more complexity ... especially in multiplayer"; keeping it purely a render-side concern avoids that.
4. Manage depth precision by changing camera `near`/`far` with altitude (Section 2.2).

---

## 8. Planet and terrain

- **No built-in spherical terrain.** Terrain3D is a planar clipmap GDExtension [S]; Zylann's Voxel Tools is a C++ **module** whose GDExtension build is still on its roadmap ("Make GDExtension work") [V], so it requires custom engine builds and breaks the standard-template/web goal. It is overkill for a non-diggable moon.
- Best reference found: `cuberact/godot-cuberact-planet-chunked-lod` (MIT, GDScript + 2 shaders, Godot 4.6+, Earth-radius planet, cube-sphere quadtree chunked LOD, horizon/frustum culling, chunk pooling; 147 stars, last push 2026-03-22). [V README]
- `Hoimar/Planet-Generator` is an older addon (quadtree, noise); age and 4.7 compatibility unverified. [S]
- **Compute shaders are unavailable in Compatibility** [V], so: generate heights on CPU (budgeted per frame; `WorkerThreadPool` only on multi-threaded builds) or displace in the vertex shader for visuals.
- **Determinism for gameplay [U]:** do not depend on `FastNoiseLite` giving bit-identical floats on every CPU/browser. Bake the moon's height field offline (Python tool) into six cube-face 16-bit height images (e.g. 6 x 2048^2, about 15 m/texel at R=20 km) plus detail noise for visuals only; server and clients read the same baked data for collision and spawning. Craters can be stamped at bake time.
- Mesh LOD, visibility ranges and MultiMesh chunking cover structures and props; horizon culling must be added by us (a chunk behind the horizon relative to camera altitude is skipped).

---

## 9. Navigation on a sphere

### 9.1 What the engine does [V: source at 4.7-stable]

- `NavigationServer3D.map_set_up(map, up)` sets **one** `up` per map. `nav_mesh_queries_3d.cpp` uses `map_up` in the funnel (string-pulling) algorithm via cross-product sign tests, and for ray/plane cuts. On a sphere that sign flips on the far hemisphere, so funnelled paths are wrong beyond about 90 degrees from `up`.
- `nav_region_3d.cpp` prints an error when a region's transform is rotated **>= 90 degrees** away from the map's `up`.
- Baking (Recast) voxelizes along the Y axis; edge-merge rasterization uses axis-aligned cells.
- Escape hatches: you can author a `NavigationMesh` by hand (`set_vertices`, `add_polygon`) and set `NavigationPathQueryParameters3D.path_postprocessing` to `EDGECENTERED` or `NONE` (no up-dependent funnel). Plausible but unproven for a sphere. [V API, U feasibility]

### 9.2 Recommendation [U]

- Ground units (builders, harvesters, rovers): **custom graph on a geodesic grid** with `AStar3D` (ids = icosphere vertex indices, custom `_compute_cost` for slope/crater/building). Icosphere vertex count = 10*4^n + 2: n=7 gives 163,842 vertices (about 160 m edges at R=20 km), n=8 gives 655,362 (about 80 m). Use a coarse level for long routes and a fine level locally; rebuild only blocked-cell weights when buildings change.
- Flying ships need no navmesh: steering behaviors, spatial-hash neighbor queries, ray casts for terrain/structure avoidance.
- Optional spike: hand-built NavigationMesh from icosphere triangles with `EDGECENTERED` postprocessing, to get agents/avoidance for free.

---

## 10. Tooling for AI-agent-driven development

### 10.1 Headless CLI [V: `[D-cli]`]

`godot --headless` = headless display driver + Dummy audio: scripts, scene tree, physics, timers and networking all run; rendering and window functions are disabled ("most DisplayServer functions return dummy values"). Useful flags:

| Flag | Use |
|---|---|
| `--headless --path <proj> --import` | build the `.godot` import cache on a clean checkout (always run first in CI) |
| `--headless --check-only -s <script.gd>` | parse a single script and quit |
| `--headless -s <runner.gd>` / `--quit-after N` | run a script or N frames |
| `--fixed-fps N` | decouple from wall clock (deterministic batch runs) |
| `--export-release <preset> <path>`, `--export-debug`, `--export-pack`, `--export-patch` | automated exports (editor binary; implies import) |
| `--lsp-port`, `--dap-port` | GDScript language server / debug adapter (editor mode) |
| `--dump-extension-api`, `--doctool` | API dumps for GDExtension / docs |
| `--rendering-method gl_compatibility`, `--rendering-driver opengl3` | choose renderer for visual CI |

### 10.2 Test frameworks (versions checked 2026-10-09) [V: GitHub]

| Framework | Version | Godot support | CLI | Notes |
|---|---|---|---|---|
| **GUT** (`bitwes/Gut`) | **9.7.1 (2026-07-10) for 4.7.x**; 9.6.1 for 4.6.x | per README table | `godot --headless -s addons/gut/gut_cmdln.gd --path . -gdir=res://test/unit -gexit -gjunit_xml_file=results.xml` (GUT's docs example also passes `-d`; omit it for agents, see gotcha below) | exit 0/1; also `-gselect`, `-gconfig`, `-glog` |
| **gdUnit4** (`godot-gdunit-labs/gdUnit4`, formerly `MikeSchulze/gdUnit4`) | **v6.2.2 (2026-10-07)** | 4.5-4.7.1 (+4.8-dev7 on master) | `addons/gdUnit4/runtest.sh -a res://test -c -rd reports` (needs `GODOT_BIN`) | exit 0 / 100 failures / 101 warnings; JUnit XML + HTML reports; scene-runner and mocking; GDScript and C#. Repo ships `CLAUDE.md`, `AGENTS.md`, `llms.txt`. |

**Agent gotcha:** gdUnit4's runner passes `--remote-debug tcp://127.0.0.1:0` so that a script parse error does not drop Godot into its interactive `debug>` prompt (an endless loop for a non-interactive agent). Any ad-hoc `godot -d` command used by agents should do the same. [V from `runtest.sh`]

**Recommendation:** gdUnit4 as primary (scene runner, input simulation, coverage of async/signals, JUnit output), GUT acceptable. One framework only, to keep agent instructions short.

### 10.3 Lint/format

- `gdtoolkit` 4.5.0 on PyPI (released 2025-10-09; also the last commit on `master` as of this check) provides `gdlint`/`gdformat`. Open issues (Sept-Oct 2026) include `@abstract` handling and multi-line lambda formatting. **Treat as advisory**: pin `gdtoolkit==4.5.0`, run `gdformat --check` in CI but do not block merges on it until proven on our code. [V]
- The authoritative guard is the engine itself (Section 4.3 warnings as Error + `--headless --import` + the test run).

### 10.4 CI and export automation [V: GitHub APIs/READMEs]

- Docker: `barichello/godot-ci` (tag **4.7.2-stable** published 2026-08-18; `mono-` variants exist). Covers Linux, Windows, Web, Android; the README still says **iOS "not available yet"** (may be stale).
- GitHub Action: `chickensoft-games/setup-godot` v2.4.3 (2026-10-01) installs Godot (+templates, +.NET optionally) on macOS, Windows and Ubuntu runners, with caching.
- GitHub-hosted runners: Ubuntu 24.04/26.04 (x64, arm), Windows 2022/2025, macOS `macos-14/15/26` (arm64) and `macos-15-intel/26-intel`; free for public repositories. [V: `[D-gha]`]
- Keystore env vars for Android: `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD` (and `_DEBUG_*`). Script-encryption key: `GODOT_SCRIPT_ENCRYPTION_KEY`.

### 10.5 Verifying scenes without a GPU

1. **Logic and scene wiring:** headless unit/integration tests; a project-owned `tools/validate_scenes.gd` that loads and instantiates every `.tscn`/`.tres`, reporting missing scripts/resources (we write this; trivial).
2. **Visual checks:** run the windowed binary under **Xvfb with Mesa software drivers** (llvmpipe for OpenGL/Compatibility, lavapipe for Vulkan). Several open-source Godot projects do this in CI; goldens must be keyed by adapter because output differs between drivers and Mesa versions. `--headless` cannot capture frames because it disables rendering. Since our baseline is the Compatibility renderer, llvmpipe is the matching path. [S, widely reported]
3. **Frame capture:** `--write-movie out.png --fixed-fps 30 --quit-after N` (needs a rendering display server, so use 2 on CI, the real GPU locally).
4. Windows dev box: the physical GPU is available, so agents can screenshot locally with the Browser/Computer tools; CI uses the Xvfb path on Linux.

### 10.6 Known risk: long headless runs

A report (godot#122707, Godot 4.7.1, 2026-08-21) claims `--headless` with any main scene slows to a crawl after ~25-55 s. It was **closed as AI-written without a technical resolution**, so it is unverified. Include a 10-minute headless soak test in the first spike. [U]

### 10.7 Godot MCP servers (GitHub API, 2026-10-09)

Third-party and unvetted: `Coding-Solo/godot-mcp` (MIT, 5,987 stars, last push 2026-04-16; launches editor, runs projects, captures debug output), `youichi-uda/godot-mcp-pro` (621 stars, paid, license "NOASSERTION"), `tugcantopaloglu/godot-mcp` (474 stars; "tested with Godot 4.7"; headless CLI plus runtime TCP), `tomyud1/godot-mcp` (433 stars, 75 tools, MIT), `IvanMurzak/Godot-MCP` (274 stars, Apache-2.0, routes via a hosted or self-hosted backend), `satelliteoflove/godot-mcp` (173 stars, input injection and deterministic playtesting, pushed 2026-10-02).

**Recommendation:** make the CLI (headless run, tests, our own scripts) the primary agent loop because it works for every model tier without extra processes. Evaluate **one** editor-connected MCP later for screenshots and live scene inspection, and review its code before giving it filesystem access.

---

## 11. Backend and services

| Service | Status (2026-10-09) | Fit |
|---|---|---|
| **Nakama** (Heroic Labs) | Server v3.41.0 (2026-09-18), Apache-2.0; official Godot client `nakama-godot` is GDScript, supports Godot 4.0+, `master` pushed 2026-09-21 (latest tagged release v3.4.0 is from 2024-03). Works on web via Godot HTTP/WebSocket adapters. | Accounts, friends, chat, leaderboards, matchmaking, storage. Good default backend; self-host on a VPS or use Heroic Cloud (pricing unverified). |
| **Talo** | Godot plugin v1.2.0 (2026-10-04) | Leaderboards, stats, saves, auth; lighter than Nakama, less control. |
| **W4 Cloud** | Open-source AGPL backend (Supabase + Agones); W4 Games' homepage now lists only consulting/ports/XR/support and **no longer mentions W4 Cloud**; docs site still up; no 2026 activity found | **Do not depend on it.** [S] |
| **GodotSteam** | Moved to **Codeberg**; v4.23 on 2026-10-05; Windows/Linux/macOS only; has server and MultiplayerPeer editions | Steam release: achievements, lobbies, Steam networking. Supported Godot/SDK versions of v4.23 unverified. |
| **Epic Online Services** | Community plugins only (EOSG by 3ddelano, Godot EOS by Flying-Rat); versions/4.7 compatibility unverified | Possible later (cross-play); not core. |
| **Edgegap** | Operating; has Godot sample (Forest Brawl + netfox); claims 615+ edge locations | Dedicated-server orchestration. WebSocket/TLS handling not verified. |
| **Gameye** | Operating; container-level, no SDK; its Godot guide was validated on 4.2-4.4 | Vendor blog, treat claims as marketing. |
| **GameFabric (Nitrado)** | Operating; Agones-based; Hathora's recommended migration | Managed Agones. |
| **Agones** | v1.61.0 (2026-09-24) | Self-managed Kubernetes fleet; overkill initially. |
| **Hathora** | **Shut down 2026-05-05** (announced 2026-03-04; acquired by Fireworks AI) | Dead: do not use. [S, several agreeing sources; Edgegap's migration page states the date] |
| **Unity Multiplay Hosting** | Support ended 2026-03-31 | Dead. |
| **Rivet** | Pivoted to "Actors"; its Godot asset-library plugin targets Godot 4.2; its site no longer has a Godot integration page | Do not depend on it. [S] |
| **Plain VPS** | n/a | Cheapest start: one Linux VM running N headless server processes, Docker + systemd; add a TLS reverse proxy for WSS. |
| **TURN/STUN** | `coturn` self-hosted, or Cloudflare Realtime TURN ($0.05/GB outbound; free with their SFU; `turn.cloudflare.com` 3478/udp, 5349/tcp TLS, 443 alternates) | Needed only if we adopt WebRTC. [V: `[D-cf]`] |

**Hosting constraint to remember for web clients [U]:** browsers on HTTPS refuse plain `ws://`. Per-match servers with ad-hoc IP:port (typical of orchestrators) need a hostname + certificate or a TLS-terminating proxy. This is a point in favour of a *fixed set of regional game hosts behind Caddy/nginx* for v1 instead of dynamic per-match allocation.

---

## 12. Mobile specifics

### 12.1 Android [V: `[D-and]`, `[D-sysreq]`, `[D-a16k]`]

- Toolchain (4.7 docs): **OpenJDK 17** (higher supported), Android SDK Platform 35, Build-Tools 35.0.1, Platform-Tools 35+, Command-line Tools latest, **NDK r28b (28.1.13356709)**, **CMake 3.10.2.4988404**; `sdkmanager` one-liner in the docs. 4.8 adds an `AndroidSDKManager` helper.
- Google Play needs an **AAB**, which needs the **Gradle build** option; release keystore via env vars. Enable the `INTERNET` permission in the preset or all networking is blocked.
- Minimum OS: Android 7.0 (Compatibility) / 9.0 (Mobile, Forward+); recommended Android 9+, iOS 16+.
- **16 KB page size:** Google Play requires 16 KB support for apps targeting Android 15+; updates that lack it are blocked from **2027-02-01**. Godot supports it since 4.5; our own native libraries (GDExtensions, `webrtc-native`) must be built with NDK r28+ (aligned by default).
- 4.7: GABE (Android build environment) stable; Perfetto tracing default on Android.

### 12.2 iOS [V: docs + source]

- Docs: "You must export for iOS from a computer running macOS with Xcode installed."
- Source reading (`editor/export/editor_export_platform_apple_embedded.cpp`, 4.7-stable): on non-macOS hosts the exporter still produces the **Xcode project** (GDScript projects) but logs ".ipa can only be built on macOS. Leaving Xcode project without building the package"; **C# + Apple export is blocked outside macOS**. So a Windows/Linux CI job can export the project and a macOS job can build/sign. [V source, not run]
- Requirements: Apple developer Team ID (10 chars) + bundle ID; iOS 15 (Vulkan) or iOS 16 (Metal); simulator supports Compatibility only; Apple Silicon Macs can run the app natively.
- Options for a Windows dev machine: GitHub-hosted macOS runners (verified labels above; free for public repos), a rented/cloud Mac, or a physical Mac mini. [V for GitHub, U for others]

### 12.3 Touch input [V: class references]

`InputEventScreenTouch`, `InputEventScreenDrag`, `InputEventPanGesture`, `InputEventMagnifyGesture`; project settings `input_devices/pointing/emulate_mouse_from_touch` and `emulate_touch_from_mouse`; Android `enable_pan_and_scale_gestures`. **4.7 adds a built-in `VirtualJoystick` control** (Fixed, Dynamic, Following modes; maps to input actions). `DisplayServer.get_display_safe_area()` and cutout rectangles exist for notches.

### 12.4 Performance tiers [U]

- **No thermal/battery-state API** found in the engine (code search of the repository returned nothing). If wanted it needs an Android/iOS plugin.
- Define three quality tiers ourselves and select by first-run micro-benchmark plus `RenderingServer.get_video_adapter_name()`/core count: scale `rendering/scaling_3d/scale`, shadow quality, MultiMesh visible counts, particle counts, physics tick (60 -> 30 Hz with interpolation), `Engine.max_fps` cap. Official minimums are low (native mobile: 1 GB RAM, web: 2 GB) but say nothing about this game's load.

---

## 13. Other Godot 4.3+ changes that matter to us

| Release | Change | Why it matters |
|---|---|---|
| 4.4 | Built-in Jolt (experimental); typed Dictionaries; Metal backend on Apple; C# Android all ABIs; 3D physics interpolation; UIDs; RD-renderer fallback chain | physics, iOS performance |
| 4.5 | `@abstract` classes/methods, variadic functions; shader baker (up to 20x faster load on Metal/D3D12, RD renderers only); web WASM SIMD; stencil buffer; 16 KB pages; 2D navigation server | cleaner GDScript architecture; shader-stutter control on Mobile renderer |
| 4.6 | Jolt default; LibGodot; delta-encoded patch PCKs; D3D12 default on Windows | live data patching |
| 4.7 | `VirtualJoystick`; `AreaLight3D`; HDR output; per-platform template downloader; GABE stable; Android picture-in-picture; SDL3 iOS controllers | mobile controls, smaller tool installs |
| 4.8-dev | Compat decals; texture streaming; Jolt 5.6; .NET 10; Emscripten 6.0.1; non-allocating physics queries | adopt after 4.8.1 |

Shader-stutter note: the **shader baker** only works with RD renderers; the Compatibility renderer has no equivalent, so pre-warm materials/particles on a loading screen (spawn one of every effect off-screen). [U]

---

## Recommendations

**R1 - Engine and renderer.** Pin 4.7.2; record the version in `docs/`, CI and the Docker tag. Author all content for **Compatibility** first (it is the common denominator across web, low-end Android and iOS simulator). Keep an optional `Mobile` renderer profile for high-end native builds only after the Compatibility look is signed off.

**R2 - Language.** Typed GDScript everywhere, warnings-as-Error (4.3). Define module interfaces so that any hot path (snapshot codec, spatial hash, A* graph, terrain mesher) has a **pure-GDScript reference implementation** and can later get a native GDExtension twin. The web build always runs the GDScript twin (`web_noextensions`), keeping single-thread hosting possible. Server and native clients may load the native twin.

**R3 - Architecture split.** Separate (a) a headless-capable **sim core** (packed arrays, no Nodes per unit, planet-centred float64), (b) a **presentation layer** (Nodes, MultiMeshes, UI), (c) a **net layer** (own protocol, transport adapters). The browser build targets online play and small local skirmishes with reduced unit caps; full-size skirmish vs AI is a native feature. [U]

**R4 - Networking.** Build the transport-agnostic protocol (Section 5.3). Order of delivery: ENet (native) + WebSocket (web, behind Caddy/nginx TLS) first; WebRTC with `webrtc-native` as a measured upgrade if WebSocket's head-of-line blocking hurts web play. Use `SceneMultiplayer` only for auth/lobby control messages (or not at all). Do not use `MultiplayerSynchronizer` for sim entities.

**R5 - World scale.** Default moon radius 10-20 km, centred at the origin, single precision, float64 sim state, camera-relative rendering switch for R > 20 km. Test the three radii (8/20/32 km) in a spike. Adaptive near/far planes.

**R6 - Terrain/nav.** Cube-sphere chunked LOD in GDScript (cuberact as reference), baked six-face height data shared by server and clients; AStar3D on an icosphere for ground units; no NavigationServer3D for the whole sphere.

**R7 - Physics.** Jolt explicitly selected; custom arcade integrator for ships; `Area3D` point gravity for any rigid-body debris/props; analytic terrain height for collisions.

**R8 - Tooling.** gdUnit4 6.2.x as the single test framework; GDScript warnings as Error; `--headless --import` then tests in CI; `godot-ci` image `4.7.2-stable` for Linux/Windows/Web/Android exports; a macOS runner job for iOS; Xvfb+llvmpipe lane for screenshots; gdtoolkit advisory only; no agent-authored upstream Godot issues/PRs. Start with the CLI loop; add one editor MCP later.

**R9 - Backend/hosting.** Nakama (self-hosted on a VPS) for accounts/matchmaking; plain Linux VPS fleet running headless Godot servers behind a TLS proxy for v1; evaluate Edgegap or GameFabric when per-match elasticity is needed. Avoid Hathora, Unity Multiplay, Rivet, W4 Cloud.

**R10 - Mobile.** Set up Android Gradle/AAB export early (JDK 17, NDK r28b, SDK 35). For iOS, rent or borrow a Mac early and prove the Xcode-project-export-on-Windows + build-on-macOS flow in a spike. Plan touch UI around `VirtualJoystick`, pinch/pan gestures and a commander-view tap-to-select model.

### Proposed P0 spikes (each 1-3 days, owner: Opus unless noted)

| ID | Spike | Pass criterion |
|---|---|---|
| S-WEB-1 | Compatibility-renderer moon (R=20 km) + 200 ships in a single-threaded web export on desktop Chrome, Firefox, Safari, Android Chrome, iOS Safari; measure wasm size, load time, FPS | >= 30 FPS on a mid-range phone browser; sizes recorded for 4.7.2 |
| S-NET-1 | Dual-listener server (ENet + WebSocket) + custom snapshot codec, 400 entities, 8 clients, simulated 100 ms RTT / 3% loss | <= 30 KB/s per client; no stalls |
| S-NET-2 | WebRTC `create_server` with `webrtc-native` on Linux, browser client with unreliable channel | connection + unreliable snapshots work |
| S-PHYS-1 | Jolt in single-thread web build + Android mid-range: 200 bodies with point gravity and 1000 ray queries per tick | frame budget recorded |
| S-PREC-1 | Radii 8/20/32 km, camera-relative rendering switch, z-fighting check | decision on max R |
| S-NAV-1 | AStar3D on icosphere n=7/8, 1000 queries | median < 5 ms |
| S-CI-1 | Clean-checkout CI: `--import`, gdUnit4 run, web+Linux+Android export, 10-min headless soak, Xvfb screenshot | green; soak shows no stall |
| S-IOS-1 | Export Xcode project from Windows, build/sign on macOS runner | installable on device |

---

## Uncertainties / unverified

1. **Web download size for 4.7.2**: only the 4.3 figures (about 40 MB raw / 5 MB Brotli) are from an official source; custom-template numbers are community reports. Not measured.
2. **Jolt behavior at runtime in single-thread web** and on mid-range mobile: build-level support verified from source, runtime and performance not tested; no official benchmarks.
3. **Double precision on web/Android/iOS:** no CI coverage seen, no official templates; whether the builds compile and run correctly was not tested.
4. **Dual/triple-transport single server** (Section 5.3) and **unreliable WebRTC to a native server**: API surface verified, end-to-end design untested.
5. **Scaling numbers**: no authoritative `MultiplayerSynchronizer` benchmarks exist; all bandwidth/CCU figures in this report are design targets or vendor anecdotes.
6. **4.8 timeline**: only "Q4 2026 (estimate)" from the docs table; no beta/RC dates published as of dev7. The "4.8.1 around Dec-Jan" estimate is mine.
7. **wasm64**: stated reverted on master (GH-122538); I did not verify whether the 4.7.x release tags still carry the flag in their web template build matrix beyond the 4.7-stable workflow, which still builds a "wasm64 + threads" template described as unusable.
8. **godot-ci iOS** note may be stale; I did not test the image.
9. **GodotSteam v4.23** supported Godot/Steamworks versions; **EOS plugins** compatibility; **Hathora/Unity** shutdown dates rely on vendor blogs and third-party reports (consistent across sources, but not Hathora's own page); **Rivet** and **W4 Cloud** status inferred from absence of information.
10. **Headless stall report (#122707)**: unverified; closed for being AI-written.
11. **gdtoolkit** compatibility with GDScript syntax added in 4.6/4.7: not tested; open issues suggest gaps.
12. **FSR1 in Compatibility**, **WorkerThreadPool in single-thread builds**, **FastNoiseLite cross-platform determinism** (a precaution, not a known defect), **Edgegap WebSocket/TLS handling**, **Heroic Cloud pricing**, **cloud-Mac options other than GitHub runners**, and **MCP server quality/safety** (only popularity and activity were checked): not verified.

---

## Sources

Docs (branch `4.7` unless noted; raw RST read from `github.com/godotengine/godot-docs`):

- `[D-policy]` https://docs.godotengine.org/en/stable/about/release_policy.html ; contribution policy: https://godotengine.org/article/contribution-policy-2026/
- `[D-web]` https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
- `[D-csharp]` https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/index.html
- `[D-render]` https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- `[D-sysreq]` https://docs.godotengine.org/en/stable/about/system_requirements.html
- `[D-jolt]` https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html
- `[D-lwc]` https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html
- `[D-mp]` https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html ; WebRTC https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html
- `[D-ded]` https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html
- `[D-and]` https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html ; `[D-ios]` https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html
- `[D-cli]` https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
- `[D-lod]` .../tutorials/3d/mesh_lod.html ; `[D-occ]` .../tutorials/3d/occlusion_culling.html ; `[D-vis]` .../tutorials/3d/visibility_ranges.html ; `[D-mm]` .../tutorials/performance/using_multimesh.html
- Typing: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html
- Web compile/dlink: https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_for_web.html

Releases and blog:

- `[D-gh-rel]` https://github.com/godotengine/godot/releases (API: `repos/godotengine/godot/releases`)
- `[D-blog]` https://godotengine.org/blog/ ; 4.7 https://godotengine.org/releases/4.7/ ; 4.6 https://godotengine.org/releases/4.6/ ; 4.5 https://godotengine.org/releases/4.5/ ; 4.4 https://godotengine.org/releases/4.4/
- Maintenance: https://godotengine.org/article/maintenance-release-godot-4-7-1/ , https://godotengine.org/article/maintenance-release-godot-4-7-2/
- `[D-dev2]` https://godotengine.org/article/dev-snapshot-godot-4-8-dev-2/ ; `[D-dev4]` .../dev-snapshot-godot-4-8-dev-4/ ; `[D-dev5]` .../dev-snapshot-godot-4-8-dev-5/ ; `[D-dev7]` .../dev-snapshot-godot-4-8-dev-7/
- `[D-web43]` https://godotengine.org/article/progress-report-web-export-in-4-3/
- Archive: https://godotengine.org/download/archive/

Godot GitHub items: wasm64 https://github.com/godotengine/godot/pull/102378 and revert https://github.com/godotengine/godot/pull/122538 ; C# web https://github.com/godotengine/godot/issues/70796 and https://github.com/godotengine/godot/pull/106125 ; WebGPU https://github.com/godotengine/godot-proposals/issues/6646 ; WebTransport https://github.com/godotengine/godot-proposals/issues/3899 ; sync prediction https://github.com/godotengine/godot-proposals/issues/7280 ; headless stall https://github.com/godotengine/godot/issues/122707.

Godot source at tag `4.7-stable` (read via raw.githubusercontent.com): `modules/jolt_physics/{config.py,SCsub,register_types.cpp}`, `modules/navigation_3d/{nav_map_3d.cpp,nav_region_3d.cpp,3d/nav_mesh_queries_3d.cpp}`, `editor/export/editor_export_platform_apple_embedded.cpp`, `platform/web/export/export_plugin.cpp`, `.github/workflows/*.yml`, `thirdparty/README.md`, `modules/mono/glue/GodotSharp/GodotSharp/GodotSharp.csproj` (also `master`), class references under `doc/classes/` and `modules/*/doc_classes/`.

Tooling and addons (GitHub API, 2026-10-09): https://github.com/bitwes/Gut ; https://github.com/godot-gdunit-labs/gdUnit4 ; https://github.com/Scony/godot-gdscript-toolkit (PyPI `gdtoolkit` 4.5.0) ; https://github.com/abarichello/godot-ci ; https://github.com/chickensoft-games/setup-godot ; https://github.com/godotengine/webrtc-native ; https://github.com/godotengine/godot-cpp ; https://github.com/godot-rust/gdext and https://godot-rust.github.io/book/toolchain/export-web.html ; https://github.com/foxssake/netfox ; https://github.com/cuberact/godot-cuberact-planet-chunked-lod ; https://github.com/Zylann/godot_voxel ; https://github.com/Coding-Solo/godot-mcp (and the other MCP repos listed in 10.7).

Services: https://github.com/heroiclabs/nakama , https://github.com/heroiclabs/nakama-godot ; https://github.com/TaloDev/godot ; https://codeberg.org/godotsteam/godotsteam ; https://www.w4games.com/ ; Hathora shutdown and market changes: https://gameye.com/blog/game-server-shake-up-2026/ and https://docs.edgegap.com/docs/tools-and-integrations/switch-from-hathora (vendor sources) ; Gameye Godot guide https://gameye.com/blog/godot-dedicated-server-hosting/ ; Agones https://github.com/googleforgames/agones ; `[D-cf]` https://developers.cloudflare.com/realtime/turn/ ; `[D-gha]` https://docs.github.com/en/actions/reference/runners/github-hosted-runners ; `[D-a16k]` https://developer.android.com/guide/practices/page-sizes
