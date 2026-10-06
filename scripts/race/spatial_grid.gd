extends Node
## Phase 13 shared XZ bucket grid (plan D5) — no class_name on purpose:
## consumers preload/duck-type it, so the global class cache never changes
## (the Phase 11/12 stale-cache lesson; probe runs via --script).
##
## One build-time spatial index over the static race world (obstacles +
## coins never move during a race): XZ buckets of CELL metres. Shapes
## register the FULL set of cells their AABB touches, so any query disc
## that can reach a shape shares at least one cell with it — query results
## are always a SUPERSET of the true hits. Consumers keep their existing
## precise distance tests (cone, segment-projection, pickup radius) and
## run them on far fewer candidates: value-identical by construction,
## brute-force-asserted in the probe and smoke.
##
## Records are stored by reference — Coins flips `collected` in place and
## the grid sees it. Registration order is deterministic (pines, rocks,
## logs, coins) and ids are stable ints, so per-record state (near-miss
## cooldowns) keys cleanly off grid ids.

const CELL := 12.0  # m — the AI avoidance probe radius (plan-chosen size)

const KIND_OBSTACLE := 0
const KIND_COIN := 1

var _records: Array = []  # id -> the registered Dictionary (by reference)
var _kinds := PackedByteArray()  # id -> kind byte
var _cells := {}  # Vector2i -> PackedInt64Array (ids whose AABB touches)
var _stamps := PackedInt32Array()  # id -> epoch last returned (dedup)
var _epoch := 0


# --- registration (build time) -------------------------------------------------


func register_disc(
	center: Vector2, radius: float, record: Dictionary, kind := KIND_OBSTACLE
) -> int:
	var box := Rect2(
		center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)
	)
	return _register_aabb(box, record, kind)


## Segment + radius (fallen logs): the swept AABB of the capsule.
func register_segment(
	a: Vector2, b: Vector2, radius: float, record: Dictionary, kind := KIND_OBSTACLE
) -> int:
	var min_p := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(radius, radius)
	var max_p := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(radius, radius)
	return _register_aabb(Rect2(min_p, max_p - min_p), record, kind)


func _register_aabb(box: Rect2, record: Dictionary, kind: int) -> int:
	var id := _records.size()
	_records.append(record)
	_kinds.append(kind)
	_stamps.append(0)
	var from_c := _cell(box.position)
	var to_c := _cell(box.end)
	for cy in range(from_c.y, to_c.y + 1):
		for cx in range(from_c.x, to_c.x + 1):
			var key := Vector2i(cx, cy)
			var ids: PackedInt64Array = _cells.get(key, PackedInt64Array())
			ids.append(id)
			_cells[key] = ids
	return id


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


# --- query (per tick) -----------------------------------------------------------


## Ids whose registered AABB's cells overlap the query disc's cells and
## whose kind matches ("" = every kind). Guaranteed superset of every
## record the precise test could accept at this radius; deduped.
func query_ids(pos: Vector2, radius: float, kind := -1) -> PackedInt64Array:
	_epoch += 1
	var out := PackedInt64Array()
	var from_c := _cell(Vector2(pos.x - radius, pos.y - radius))
	var to_c := _cell(Vector2(pos.x + radius, pos.y + radius))
	for cy in range(from_c.y, to_c.y + 1):
		for cx in range(from_c.x, to_c.x + 1):
			var ids: PackedInt64Array = _cells.get(Vector2i(cx, cy), PackedInt64Array())
			for id in ids:
				if _stamps[id] == _epoch:
					continue  # already returned (shape spanning cells)
				_stamps[id] = _epoch
				if kind >= 0 and _kinds[id] != kind:
					continue
				out.append(id)
	return out


func get_record(id: int) -> Dictionary:
	return _records[id]


func record_count() -> int:
	return _records.size()


## F3 / smoke observability (repo debug-state pattern).
func get_debug_state() -> Dictionary:
	return {
		"records": _records.size(),
		"cells": _cells.size(),
		"cell_size": CELL,
	}


# --- level assembly (mount + fill from the game-side record contracts) ---------


## Builds the index over a mountain level's Obstacles + Coins records.
## Call from the level root's _ready AFTER its scene children are built
## (their _ready runs first — children before parent, engine order).
func build_from_level(level: Node) -> void:
	var obs := level.get_node_or_null("Obstacles")
	if obs != null:
		for kind_name in ["pines", "rocks"]:
			for rec in obs.call("get_obstacles", kind_name):
				var p: Vector3 = rec["pos"]
				register_disc(Vector2(p.x, p.z), float(rec["r"]), rec)
		for rec in obs.call("get_obstacles", "logs"):
			var p: Vector3 = rec["pos"]
			var ax: Vector3 = rec["axis"]
			var hl: float = rec["half_len"]
			register_segment(
				Vector2(p.x - ax.x * hl, p.z - ax.z * hl),
				Vector2(p.x + ax.x * hl, p.z + ax.z * hl),
				float(rec["r"]),
				rec
			)
	var coins := level.get_node_or_null("Coins")
	if coins != null:
		for rec in coins.call("get_records"):
			var p: Vector3 = rec["pos"]
			register_disc(Vector2(p.x, p.z), 0.0, rec, KIND_COIN)
