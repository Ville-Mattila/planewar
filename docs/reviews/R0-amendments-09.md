# R0 amendments 09: the NET-04 contract question (PR #81): the ORDER payload header is 9 bytes, so a 32-id ORDER carries 14 points and a 32-id ESCORT is 143 B

| Field | Value |
|---|---|
| **Register id** | R0 Part B, new subsection B.16 (append-only). No ADR is amended, so no `docs/adr/ADR-NN-amendment-*.md` and no line in 01's amendment log (10 s4.2): A-91 is a doc erratum of the A-26 / A-60 kind (a printed size formula that disagrees with its own field list) and an acceptance re-baseline backed by the merged bytes; the wire **layout** does not change. |
| **Status** | Decided by the Architect 2026-10-21; the OWNER item below carries its default until the owner rules. |
| **Date** | 2026-10-21 |
| **Raised by** | NET-04 (PR #81): "Contract question (Architect): ORDER header is 9 bytes, not 8". |
| **Decided by** | Architect (Fable), 10 s4.1 "Change" row (an acceptance figure and a `MODULE.md` constant of a merged lane change; 10:259); acceptance strings and `backlog.json` are the Architect's (10:276); the owner approves the OWNER item. |
| **Size** (10 s4.1) | One formula erratum in 04 s2.5 with three derived numbers (A-91); one constant value in `sim/orders/MODULE.md` (`WIRE_HEADER_BYTES` 8 -> 9) and the one test line that asserts it; two acceptance re-baselines (NET-04, TA-60's recorded figure). No enum change, no reorder, no delete, no def key, no `deps.json` edge, no new autoload, addon or thread, no byte on the wire moves. |

Reading order for the NET-04 author and the sim engineer of TA-62: the B.16 row in `docs/reviews/R0-resolution-register.md` is the binding text; this file is the why. The Architect edits no `godot/src/**/*.gd`, no `MODULE.md` and no test; the code consequences are listed per task at the end.

## A-91 (NET-04) the ORDER header is 9 bytes; 04 s2.5's `8 +` is the erratum, not the layout

**Evidence.** The 04 s2.5 ORDER field list (04:227-234) is `u8 order_kind, u8 flags, u8 haul_mode, u8 count, u32 ids[count], u32 target, u8 point_count, vec3q points[point_count]`. The fixed part sums to 4 + 4 + 1 = **9** bytes; the printed size `8 + 4 * count + 8 * point_count` (04:242) omits `point_count`'s byte. The merged sim already writes 9: `Command.order` (`godot/src/sim/command.gd:28`, TA-18 / TA-60) sizes the sim form as `9 + 4 * n + 24 * pts.size()` and puts `point_count` at offset `8 + 4 * n`; `CommandPayload.read_order` (`godot/src/sim/world/command_payload.gd:24-30`) rejects a payload shorter than `9 + 4 * n` and reads `point_count` at `8 + 4 * n`. Only `OrderSpec.WIRE_HEADER_BYTES = 8` (`godot/src/sim/orders/order_spec.gd:24`) and the two lines of `test_wire_size_arithmetic_matches_04` that assert `wire_size(32, 15) == 256` and `wire_size(32, 0, ESCORT) == 142` (`godot/test/unit/sim/orders/test_order_rules.gd:175,182`) repeat the printed formula. NET-04's codec (PR #81, `CommandCodec.ORDER_HEADER_BYTES = 9`) encodes the field list and its `test_every_sim_builder_matches_net_bytes` shows the net bytes equal `Command.order`'s for every non-positional kind; `test_order_32_ids_14_points_is_249_bytes_15_refused` and `test_escort_32_ids_is_143_bytes_and_slot_none` measure the real boundary. The history confirms the direction of the error: the original NET-04 acceptance and 09 s2.3 (09:286, still unchanged) said "a 32-id, 14-point ORDER round-trips and a 15-point one is refused"; A-60 (amendments 04) moved the acceptance to 15 by trusting the printed `8 +` over the field list, and A-85 (amendments 07) derived 142 B from the same formula while explicitly leaving A-60 "untouched". With the correct header: `9 + 128 + 112 = 249` B for 14 points, `9 + 128 + 120 = 257` B for 15 (> 256), and `9 + 128 + 6 = 143` B for a 32-id ESCORT.

**Decision.**

1. **The layout stands; the formula is corrected.** 04 s2.5 (04:242) reads: *Size = `9 + 4 * count + 8 * point_count + (6 if ESCORT)` <= 256 B, so a 32-unit selection carries at most 14 points (9 + 128 + 112 = 249; 15 points = 257 B and V-ORD rejects it as REJECTED_MALFORMED). ESCORT carries no points, so its largest payload is 143 B.* No byte on the wire moves: every `u8` of the field list stays where TA-18, TA-60 and PR #81 put it, and `PROTOCOL_VERSION` stays 1. The 16-point cap of `point_count` is unchanged; it is reachable with up to 29 ids (`9 + 116 + 128 = 253`), which covers the 08 SL-4 routes (FEAT-15's "16 waypoints fit 256 B" is a one-id route and stays true).
2. **Not accepted: changing the layout to keep 15 / 142.** Dropping `haul_mode` into `flags` bits or packing `point_count` into `count` would save the byte but change bytes the sim already reads (TA-18, TA-60 merged, `test_order_rules.gd`, `test_command_payload.gd`), re-open 05 s3.1's HAUL semantics for one waypoint nobody asked for (PATROL is 2-8 points, 05 s3.2; every other v1 kind is 0-1), and contradict A-85's reason for the trailer (keep the header stable, append). Raising the 256 B cap: rejected; 04 s2.5 and 03's COMMAND envelope size it, NET-16's V-ORD and NET-23's fuzz corpus key on it.
3. **A-60 and A-85 figures are superseded** in their numbers only: A-60 reads "14 round-trips, 15 refused"; A-85's "max 142 B" reads 143 B. Everything else in both rows (the trailer, `REJECTED_MALFORMED` rules, the sim form `9 + 4n + 24np + (6 if ESCORT)`, which was already right) stands. The register rows get a trailing pointer to this row; nothing is reordered or removed.
4. **The sim fix is a task, not a review note:** **TA-62** (sim, Sonnet, 0.25 d) sets `OrderSpec.WIRE_HEADER_BYTES = 9`, re-baselines `test_wire_size_arithmetic_matches_04` to the corrected numbers, rewrites the `sim/orders/MODULE.md` open item that still says "04 s2.5 says 14; the arithmetic of its own formula gives 15" (the formula was the error), and has `Command.order` / `CommandPayload.read_order` derive their `9` from `OrderSpec.WIRE_HEADER_BYTES` so one constant owns the header. `fits_wire(32, 14)` becomes the top of the range and `fits_wire(32, 15)` false; `fits_wire(1, 16)` stays true (141 B).
5. **What NET-04 asserts** (acceptance below): a 32-id, 14-point ORDER round-trips at 249 B and a 15-point one is refused by `order_fits` and by `decode_payload` (257 B > `Protocol.COMMAND_PAYLOAD_MAX`); a 32-id ESCORT is 143 B; `CommandCodec.ORDER_HEADER_BYTES == OrderSpec.WIRE_HEADER_BYTES` and `CommandCodec.order_wire_size(32, 0, true) == OrderSpec.wire_size(32, 0, OrderSpec.Kind.ESCORT)`, so the two constants can never drift again; and the existing byte-equality with `Command.order`. The two equality assertions need TA-62 on `main`, so **NET-04 gains `depends_on` TA-62** and merges after it (TA-62 is a quarter day; the alternative, merging NET-04 with the sim constant still at 8, leaves `main` with two disagreeing contract constants for a wave, which is exactly the state this question found). **OWNER:** the merge order (TA-62 before NET-04); default applied.
6. **NET-16 / NET-23 / FEAT-15** are unaffected in text: V-ORD (04 s11.3, 04:1169) says "size <= 256 B" and names no header size; the fuzz harness reads `CommandCodec`; FEAT-15's route fits as shown in (1).

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

```json
{
  "new": [
    {"id": "TA-62", "title": "sim: OrderSpec.WIRE_HEADER_BYTES 8 -> 9 (the 04 s2.5 field list sums to 9; R0 B.16 A-91); wire_size / fits_wire re-baselined (32 ids: 14 points = 249 B, 15 refused; 32-id ESCORT 143 B); Command.order and CommandPayload.read_order derive the header from the constant; sim/orders/MODULE.md open item rewritten", "lane": "sim", "tier": "Sonnet", "size_days": 0.25, "depends_on": ["TA-60"], "milestone": "M3", "acceptance": "OrderSpec.WIRE_HEADER_BYTES == 9; test_wire_size_arithmetic_matches_04 asserts wire_size(1, 0) == 13, wire_size(32, 14) == 249, fits_wire(32, 14) true, fits_wire(32, 15) false, fits_wire(1, 16) true (141 B), fits_wire(29, 16) true (253 B), fits_wire(30, 16) false, wire_size(32, 0, ESCORT) == 143, fits_wire(32, 15, ESCORT) false; no literal 9 header offset remains in command.gd / command_payload.gd (derived from OrderSpec.WIRE_HEADER_BYTES; bytes written unchanged, every existing payload test untouched); sim/orders/MODULE.md constant line reads 9 and its NET-04 / NET-16 open item cites R0 B.16 A-91 instead of the 14-vs-15 arithmetic note; gen_module_api --check green", "docs": ["R0-amendments-09 A-91", "04 s2.5"], "status": "todo"}
  ],
  "acceptance_replace": {
    "NET-04": "Encode/decode test per kind; a 32-id, 14-point ORDER round-trips (249 B) and a 15-point one is refused by order_fits and decode_payload (257 B > 256; 04 s2.5 as corrected by R0 B.16 A-91); CommandCodec.ORDER_HEADER_BYTES == OrderSpec.WIRE_HEADER_BYTES and CommandCodec.order_wire_size(32, 0, true) == OrderSpec.wire_size(32, 0, OrderSpec.Kind.ESCORT) asserted so the net and sim constants cannot drift; net bytes equal Command.order's bytes for every non-positional kind and are a fixed point for positional kinds; malformed payload returns null"
  },
  "acceptance_append_replace": {
    "NET-04": "; the ORDER codec writes / reads the 6-byte ESCORT trailer (present iff order_kind 3): an ESCORT with slot 1, FOCUS and a focus id round-trips, a 32-id ESCORT is 143 B (A-91; A-85's 142 superseded), a MOVE with 6 trailing bytes returns null (R0 B.14 A-85); SET_RALLY (3 x f64 position) and TOGGLE_AUTO_REPLENISH (u8 flag + up to 8 x (u16 def, u8 count)) payloads round-trip as GD-17 applies them; ESCORT escort_mode > BREAK decodes to null (mirrors sim read_order, TA-60)"
  },
  "depends_on_append": {
    "NET-04": ["TA-62"]
  },
  "note": {
    "NET-04": "A-60's 15 points and A-85's 142 B came from 04 s2.5's printed `8 +` formula; the field list sums to 9 and the merged sim writes 9 (R0 B.16 A-91). Merges after TA-62 so the drift assertions pass on main.",
    "TA-60": "the recorded '32-id ESCORT is 142 B' figure is superseded by 143 B (R0 B.16 A-91); the trailer bytes and every REJECTED_MALFORMED rule stand; the constant fix is TA-62.",
    "AI-01": "A-60's '15 points' was the erratum: the original 14 stands (R0 B.16 A-91)."
  }
}
```

## Consequences for PR #81 (review findings, not new contract)

1. The PR body's "NOT MET as written" row closes against A-91: the acceptance -> evidence table reads "32 ids: 14 points round-trip at 249 B, 15 refused; 32-id ESCORT 143 B: pass (R0 B.16 A-91)". The `net/MODULE.md` sentence "not the 15 / 142 of A-60 / A-85 (04's `8 +` omits point_count; contract question open)" reads "04 s2.5 as corrected by R0 B.16 A-91".
2. After rebasing on TA-62, `test_command_codec.gd` adds the two equality assertions of A-91 (5); `ORDER_HEADER_BYTES` may stay a `net` constant or become an alias of `OrderSpec.WIRE_HEADER_BYTES` (`OrderSpec` is one of `net`'s named sim types in `tools/deps.json`; the author's choice, the test is the contract).
3. Everything else in the PR (the 16 codecs, the envelope, the fuzz smoke, PILOT_INPUT refusal) is inside the `net` contract and needs no Architect ruling.

## Not ruled here

Whether `Command.order` should refuse a selection or point count that does not `fits_wire` at build time (today the sim form has no 256 B cap because it carries f64 points; the cap is the codec's and V-ORD's); whether NET-16's V-ORD should cite `OrderSpec.fits_wire` or `CommandCodec.order_fits` (server lane choice; both agree after TA-62).
