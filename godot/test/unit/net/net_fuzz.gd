class_name NetFuzz extends RefCounted
## Seeded byte mutations for decoder fuzz tests (net N5: 100,000 mutations per message id, zero script errors):
## 1-4 rounds of byte set / bit flip / truncate / append / remove, biased toward the first `header` bytes.

const MUTATIONS: int = 100000


static func mutate(rng: RandomNumberGenerator, src: PackedByteArray, header: int = 8) -> PackedByteArray:
	var b: PackedByteArray = src.duplicate()
	for _r: int in rng.randi_range(1, 4):
		if b.is_empty():
			var _a: bool = b.push_back(rng.randi() & 0xFF)
			continue
		match rng.randi_range(0, 5):
			0:
				b[rng.randi_range(0, b.size() - 1)] = rng.randi() & 0xFF
			1:
				var at: int = rng.randi_range(0, b.size() - 1)
				b[at] = b[at] ^ (1 << rng.randi_range(0, 7))
			2:
				b = b.slice(0, rng.randi_range(0, b.size()))
			3:
				var _p: bool = b.push_back(rng.randi() & 0xFF)
			4:
				b.remove_at(rng.randi_range(0, b.size() - 1))
			_:
				b[rng.randi_range(0, mini(b.size() - 1, header))] = rng.randi() & 0xFF
	return b
