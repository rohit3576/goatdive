extends Node
## Global signal hub. Unconnected for now — consumed from Phase 6 (race system).

signal race_started
signal race_finished(final_time: float)
signal goat_landed(impact_speed: float)
