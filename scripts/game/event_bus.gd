extends Node
## Global signal hub. goat_landed/jumped/bonked are consumed by the Phase 4
## camera; race signals wait for Phase 6.

signal race_started
signal race_finished(final_time: float)
signal goat_landed(impact_speed: float)
signal goat_jumped
signal goat_bonked(impact_speed: float)
