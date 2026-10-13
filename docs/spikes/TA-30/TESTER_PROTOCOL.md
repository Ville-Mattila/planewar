# S-FLIGHT-1 tester protocol (TA-30)

Pass criteria under test (03 s14.6, R0 C3-02): three novice testers land within 10 minutes; fewer than 20 % of
landing attempts in minutes 5-10 end in a crash; a Raw (mouse) tester lands within 15 attempts; keyboard + mouse,
gamepad and touch; median "feels like a plane" >= 4/5. Landing is tail-down only (R0 O-2).

## Setup (facilitator)

- Build: the web test build (`web/site/play/`, CI artifact `web-spike-flight`) or the Windows editor:
  `godot --path godot res://spikes/s_flight_1/flight_spike.tscn`. Android: the same scene in a debug APK.
- Testers: three novices (never played a flight game with gravity-lander controls) plus the owner.
- Each tester plays **10 minutes per input class** (KBM, gamepad, touch), one fresh session per class
  (reload the page / restart). Order rotates between testers (A: KBM, pad, touch; B: pad, touch, KBM; C: touch, KBM, pad).
- Assist tier: novices play **FULL** (KBM: press F3 once; gamepad and touch start in FULL). One tester additionally plays
  a **Raw mouse** session (KBM, default RAW, mouse aim; no auto-dock) until the first landing or 15 attempts.
- Do not coach after the 1-minute briefing. Note the clock time of the first successful landing.
- After each session: tuning panel (F1 / gamepad D-pad up) -> "Save telemetry CSV". On web this downloads
  `flight_log_<session>.csv`; on desktop the file is in `%APPDATA%/Godot/app_userdata/PLANEWAR/s_flight_1/`.
  Collect every CSV into `docs/spikes/TA-30/testers/<tester>_<class>.csv`.

## Briefing (read aloud, 1 minute)

"You fly a small spaceship on a moon. Gravity pulls you down all the time. To land you point the nose straight up,
hover on the engine and sink slowly onto the yellow pad, tail first. The three bars on the right turn green when your
sink speed, sideways drift and nose angle are safe. In FULL you can hold DOCK near the pad and the ship lands itself."

## Task card (each session)

1. Take off from the pad (thrust).
2. Hit 5 air targets (red diamonds) with the gun.
3. Bomb 2 ground targets (orange boxes). The white ring on the ground is where a bomb would land; it turns green on target.
4. Fly back to the pad (cyan marker "PAD") and land tail-down. Repeat landings until the 10 minutes are over.

## Controls

| Action | Keyboard + mouse | Gamepad | Touch |
|---|---|---|---|
| Thrust | W hold (F5: lever, W/S steps 25 %) | RT | left slider (sticky; FULL: target speed) |
| Pitch / roll | mouse aim (click to capture; Esc frees), arrows | left stick | stick zone (appears under the thumb) |
| Roll override / yaw | A / D, Q / E | LB / RB yaw | auto |
| Brake | S | LT | BRAKE |
| Boost | Shift | L3 | BOOST |
| Gun / bomb | LMB or Ctrl / RMB or V | A / B | FIRE / BOMB |
| Flip | Space | Y | flick up on the stick |
| Auto-dock (FULL) | F hold | X hold | DOCK hold |
| Tier FULL/RAW, respawn, panel | F3, Backspace, F1 | Back, Start, D-pad up | panel via keyboard only |

## Questionnaire (5-point, 1 = disagree, 5 = agree), after each session

1. It feels like a plane.
2. Gravity is readable (I can tell when I am falling).
3. I know where the ground is.
4. Bombing is predictable.
5. Free text: what was hardest?

## What the facilitator fills in

| Tester | Class | Tier | Time to first landing (min:s) | Attempts to first landing | Crashes in min 5-10 / attempts in min 5-10 | Q1-Q4 |
|---|---|---|---|---|---|---|

The CSV gives the same numbers: `landing_attempt` rows (outcome, grade, v_vert, v_hor, tilt), `crash` rows with
`near_pad=true`, the `first_landing` row (`s_since_class_start`), `target_hit` rows with distance and height
difference (co-altitude hits: `dalt_m` within +-30 m), `aoa_sample` rows (cruise AoA), `tuning` rows.
