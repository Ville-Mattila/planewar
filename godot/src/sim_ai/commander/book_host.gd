class_name BookHost extends RefCounted
## What an `OpeningBook` needs from the bot that runs it (05 s7.3): the abstract side of the interpreter, so the book logic
## is tested without a world. Every action answers an `OpeningBook.Out`: DONE (the command was issued and accepted), WAIT
## (not now: funds, queue full, no unit free, no command left this think; try again), REJECT (the sim refused the site:
## REJECTED_PLACEMENT; `next_k` is the candidate to try next), FAIL (the step can never run: skip it). The base refuses
## everything with FAIL.

var next_k: int = 0   ## after a REJECT from `build`: the candidate index the next attempt starts at


## A friendly unit stands inside the presence radius of the site `tok` resolves to (02 AR-1; the Outpost rule).
func presence(_tok: SiteToken, _def_id: int) -> bool:
	return false


## The step's cost is covered by the team stockpile right now.
func affordable(_kind: int, _def_id: int, _n: int) -> bool:
	return false


## Places one `def_id` at the `k`-th candidate of `tok`; `issued` = how many of this step are already placed.
func build(_def_id: int, _tok: SiteToken, _k: int, _issued: int) -> int:
	return OpeningBook.Out.FAIL


## Queues `count` (1-5) units of `def_id` at the factory that makes them.
func produce(_def_id: int, _count: int) -> int:
	return OpeningBook.Out.FAIL


## Sets the auto-replenish target of `def_id` to `n`.
func replenish(_def_id: int, _n: int) -> int:
	return OpeningBook.Out.FAIL


## Orders the nearest free own unit of `classes` (def ids) to `kind` toward the site `tok` names.
func order(_kind: int, _classes: PackedInt32Array, _tok: SiteToken) -> int:
	return OpeningBook.Out.FAIL


## `raid` step (military manager, AI-27): `target` / `with` as written in the book.
func raid(_target: StringName, _with: StringName) -> int:
	return OpeningBook.Out.FAIL
