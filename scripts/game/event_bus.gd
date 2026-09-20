extends Node
## Global signal hub. goat_landed/jumped/bonked are consumed by the Phase 4
## camera and Phase 8 telemetry. Since Phase 7's herd, ALL goats emit into
## one bus — every goat signal carries its emitter so per-goat consumers
## (camera FX, per-racer telemetry) can attribute (Phase 8, plan Step 5).

signal race_started
signal race_finished(final_time: float)
signal checkpoint_passed(idx: int, split: float, racer: String)
signal goat_landed(impact_speed: float, goat: Node3D)
signal goat_jumped(goat: Node3D)
signal goat_bonked(impact_speed: float, direction: Vector3, goat: Node3D)
## Phase 8 D8: fired ALONGSIDE goat_bonked when the collider belongs to the
## "obstacles" group (corridor body) — difficulty telemetry counts these,
## never goat-goat bumps or terrain bonks.
signal goat_hit_obstacle(impact_speed: float, goat: Node3D)
