# R0 amendments 26: snapshot mask bit 6 and the retired `MASK_CELL_CHANGED` symbol (NET-61 PR #187, one Architect question from its Opus review plus two contract notes)

| Field | Value |
|---|---|
| **Register id** | R0 Part B, subsection B.32 (append-only): A-156 added 2026-11-26. Parts B.1-B.31 are unchanged. No ADR is amended; no enumeration, `deps.json` edge, autoload, addon or thread change. The wire change (`PROTOCOL_VERSION` 1 -> 2, the barrel byte) is the one B.31 A-152 already named; this row adds nothing to it. |
| **Status** | Decided by the Architect 2026-11-26. No OWNER item; the owner may overrule item 1 of "Decisions for the owner". |
| **Raised by** | NET-61 (PR #187), Opus review comment 7196609286, verdict "escalate (Architect)": one question (bit 6 and the deleted symbol) and two non-blocking contract notes. Everything else in the PR is approved by that review. |
| **Decided by** | Architect (Fable), 10 s4.1 (the "Reorder / delete / rename" row; a new invariant and a trailing defaulted parameter are Appends) and B.31 A-152. |
| **Size** (10 s4.1) | One register row, one acceptance append, one dependency append. The Architect edits no `godot/src/**`, no `godot/test/**`, no schema, no def, no `MODULE.md`, no `backlog.json`. |

Reading order: the B.32 row in `docs/reviews/R0-resolution-register.md` is the binding text; this file is the why, the author's work list and the backlog patch.

**Outcome for PR #187 in one line:** the wire design is ratified as built (bit 6 = BARREL under `PROTOCOL_VERSION` 2); the PR may not delete `SnapshotCodec.MASK_CELL_CHANGED` and restores it as a deprecated symbol; it adds one invariant. Three small edits, listed under "What PR #187 changes before merge".

## A-156 (1) Bit 6 as BARREL: covered by A-152

**Decision.** Ratified as built. No second Architect round was needed for the bit.

- A-152 delegated "the exact placement" to NET-61 and reserved only two cases for the Architect: a new message id, or a larger tier B record. The PR needs neither.
- A mask bit is wire layout. Wire layout is versioned by `PROTOCOL_VERSION` (04 s2.2; `net/MODULE.md` line 5), and A-152 ordered the bump. It is not an R0 B.3 enumeration, so the frozen-ordinal rule does not apply to it.
- No v1 packet ever carried bit 6. Checked on `main` at c70d216: `snapshot_decoder.gd:278` rejects `(m & 0xC0) != 0` as MALFORMED, `tools/replay_inspect.py:358` rejects `mask & 0xC0`, and the encoder sends a cell change as a FULL record. R0 Part B does not mention the bit. A v1 peer is refused on the version (04 s2.2), so no old client can read the new meaning.
- The 04 s2.2, s2.3, s3.3, s3.4 and s3.7 patches in the PR stand as written, including "it was CELL_CHANGED, never sent".

## A-156 (2) Deleting `SnapshotCodec.MASK_CELL_CHANGED`: not covered

**Decision.** 10 s4.1 stands. The symbol stays, deprecated.

- 10 s4.1: removing a public symbol is "Forbidden in v1. Add the new thing, deprecate the old in `MODULE.md` 'Open items', delete at a major version only, by ADR." A-152 grants a placement. It does not grant a deletion, and an R0 row cannot grant one: only an ADR at a major version can.
- The rule has no "dead symbol" exception, and this ruling does not invent one. That the constant is unused is the reason the deprecation costs one line, not a reason to skip it.
- **What stays:** `const MASK_CELL_CHANGED: int = 0x40` in `godot/src/net/snapshot_codec.gd` and in the `SnapshotCodec` line of `net/MODULE.md` Public API. Same name, same type, same value as on `main`.
- **What it means from now on:** nothing on the wire. It is the v1 name of bit 6 and has the same value as `MASK_BARREL`. No code in `godot/src/**` references it apart from its declaration. Tests may keep using it to build a malformed mask (bit 6 on an entity whose def has no barrel is still MALFORMED) or switch to `MASK_BARREL`.
- The reviewer's concern, "an alias would name a bit that now means BARREL", is answered by the Open items entry: the name is marked deprecated and wire-meaningless, and `MASK_BARREL` is the only name the codec uses.
- Deletion: at v2.0, by ADR, with the other deprecated symbols. No task is filed for it now.

## A-156 (3) Contract note 1: the server and client barrel tables must agree

**Decision.** Accepted: one invariant in `net/MODULE.md` (an Append, written by the NET-61 author in PR #187) and one NET-15 acceptance clause.

Why it earns an invariant: a FULL record has no length field. If the server fills a row of a barrel def without `set_barrel`, the record is one byte shorter than the client's `SnapshotDecoder.barrel_def` expects, the parse runs off the record, and the whole packet is MALFORMED (N10 then changes nothing). With `gravity_def` a mismatch only costs dead-reckoning accuracy; here it costs every snapshot that carries the entity. Today only test rigs fill a `SnapshotFrame`; NET-15 writes the first production filler.

**Invariant text (N11; the author may tighten the wording but not the rule):**

> N11: a `SnapshotFrame` row has `barrel != 0` exactly when its def has a barrel by the rule of R0 B.31 A-151, the rule `NetDefs.barrel_def` encodes and `SnapshotDecoder.barrel_def` reads. Every filler calls `set_barrel(i, NetDefs.barrel_byte(def_id, elevation))` after `set_entity` for every row, with a `NetDefs` built from the same `ContentSet` the clients load. A row that disagrees makes every packet that carries it MALFORMED (R0 B.32 A-156).

`net/MODULE.md` is at 300 lines; the invariant has to fit inside the limit (join it to the NET-61 sentence of "Wire layout" or re-wrap two lines).

## A-156 (4) Contract note 2: trailing optional parameters are Appends

**Decision.** Confirmed as Appends. `put_full`, `put_full_words`, `put_delta`, `set_full`, `set_full_cached`, `set_delta` and `KeyframeCodec.size_for` each gain one trailing parameter with a default.

- Every existing call site compiles unchanged and the default reproduces the old behaviour (no barrel byte). That is the 10 s4.1 Append shape, the same as "a new optional def field with a default".
- None of the owning classes is extended anywhere in `godot/` (checked on `main`), so no override breaks.
- `net/MODULE.md` and `net/keyframe/MODULE.md` show the defaults, as the PR already does.
- A parameter without a default, a reordered parameter or a changed return type remains a Change.

## What PR #187 changes before merge (author)

Required (one push, squash merge):

1. **Restore the symbol.** `godot/src/net/snapshot_codec.gd`: `const MASK_CELL_CHANGED: int = 0x40` next to `MASK_BARREL`, with a comment "deprecated (R0 B.32 A-156): the v1 name of bit 6, never sent; use MASK_BARREL". The file is at 400 lines and stays at or under 400.
2. **`godot/src/net/MODULE.md`.** (a) Public API, `SnapshotCodec` line: `const MASK_CELL_CHANGED: int` is listed again beside `const MASK_BARREL: int`. (b) Open items: "`SnapshotCodec.MASK_CELL_CHANGED` (0x40) is deprecated since NET-61: it has no wire meaning and equals `MASK_BARREL`; do not use it; deleted at a major version by ADR (10 s4.1, R0 B.32 A-156)". (c) Invariants: N11 as above. The file stays at or under 300 lines.
3. **One contract assertion.** In `godot/test/unit/net/` (the malformed or protocol suite): `SnapshotCodec.MASK_CELL_CHANGED == 0x40` and `== SnapshotCodec.MASK_BARREL`.
4. **PR body.** "Contract impact: change (R0 B.31 A-152; R0 B.32 A-156)".

Nothing else changes. The review's nits stay optional. The re-review is items 1-3 only, and this is the author's first round on this root cause (the review's own note).

## Backlog patch (proposed; the owner approves, the orchestrator lands it; `backlog.json` is not edited here)

No new task, so no new id. Checked on `main` at c70d216: NET-15 is `todo` and already has an `acceptance_append` (R0 B.19 A-101), so the text below is appended to that field; NET-61 is the highest NET id; A-156, B.32 and `R0-amendments-26.md` are unused.

```json
{
  "acceptance_append": {
    "NET-15": "; R0 B.32 A-156: ServerSession fills every SnapshotFrame row with set_entity and then set_barrel(i, NetDefs.barrel_byte(def_id, SimView.barrel_elevation(id))) (net/MODULE.md N11); a LocalTransport test whose scene holds a Siege Crawler with a slewed barrel asserts zero MALFORMED snapshot decodes on every client and NetSimView.barrel_elevation within one quantum of the server's value on a client that holds the Crawler at tier A"
  },
  "depends_on_append": {
    "NET-15": ["NET-61"]
  },
  "note": {
    "NET-61": "Ruling R0-amendments-26 (B.32 A-156): bit 6 = MASK_BARREL is covered by A-152; SnapshotCodec.MASK_CELL_CHANGED stays as a deprecated symbol (10 s4.1); net/MODULE.md gains N11; the trailing optional parameters are Appends."
  }
}
```

NET-15 is M3 and NET-61 is M4. The dependency is still correct: NET-61 is in review now and lands before NET-15 opens (NET-15 also waits for NET-08, in review). No size or tier change: the clause is one call per row and one test scene.

## Not ruled here

- **Splitting `snapshot_codec.gd` and `net_sim_view.gd`** (both at 400 lines, the review's nit). The next task that touches either does the split; it needs no Architect while the Public API is unchanged.
- **A debug-time guard in the encoder** that compares `SnapshotFrame.barrel` with a def table. The invariant and the NET-15 test cover the failure; the net lane may add a guard on its own if it costs nothing in release.

## Decisions for the owner

1. `MASK_CELL_CHANGED`: keep it as a deprecated symbol until v2.0 (10 s4.1 as written). Alternative: an ADR amendment that lets a never-used public symbol be deleted inside v1. Recommendation: keep it; one constant does not justify an ADR. Default if silent: keep it.
2. The backlog patch: NET-15 gains the A-156 clause and depends on NET-61. Recommendation: as written. Default: as written.
