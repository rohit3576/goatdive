class_name MountainCatalog
extends RefCounted
## Phase 10 — Multi-Mountain Catalog (Decision D5).
## Defines the 5 distinct procedural alpine environments:
## 1. Alpine Valley (Seed 1337) — Beginner
## 2. Rocky Ridge (Seed 2048) — Intermediate
## 3. Snow Mountain (Seed 4096) — Advanced (Ice / Low Grip)
## 4. Canyon Run (Seed 8192) — Expert (High Warp / Steep Gorges)
## 5. Extreme Summit (Seed 9999) — Master (Maximum Vertical Drop)
##
## Phase 13 D6: grid_high/grid_low are the per-mountain terrain density
## overrides. HIGH (192) is the untouched desktop default — the gauntlet's
## physics path; LOW (128) halves trimesh tris for the web candidate.
## Per-mountain tuning to 96 lands with Phase 14's on-device numbers.

const MOUNTAINS: Dictionary = {
	"alpine_valley": {
		"id": "alpine_valley",
		"name": "Alpine Valley",
		"subtitle": "Rolling green meadows & gentle fall lines",
		"seed_value": 1337,
		"grid_high": 192,
		"grid_low": 128,
		"peak_height": 260.0,
		"snow_line": 170.0,
		"warp_strength": 60.0,
		"ridge_amp": 34.0,
		"detail_amp": 3.5,
		"band_height": 10.0,
		"band_tread": 0.5,
		"band_rise": 0.35,
		"fog_density": 0.003,
		"sky_energy": 1.2,
		"unlock_level": 1,
		"difficulty": "Beginner",
	},
	"rocky_ridge": {
		"id": "rocky_ridge",
		"name": "Rocky Ridge",
		"subtitle": "Jagged granite ledges & steep cliff bands",
		"seed_value": 2048,
		"grid_high": 192,
		"grid_low": 128,
		"peak_height": 290.0,
		"snow_line": 190.0,
		"warp_strength": 85.0,
		"ridge_amp": 44.0,
		"detail_amp": 4.5,
		"band_height": 14.0,
		"band_tread": 0.4,
		"band_rise": 0.45,
		"fog_density": 0.0035,
		"sky_energy": 1.1,
		"unlock_level": 2,
		"difficulty": "Intermediate",
	},
	"snow_mountain": {
		"id": "snow_mountain",
		"name": "Snow Mountain",
		"subtitle": "Glaciated alpine descent with low-friction ice",
		"seed_value": 4096,
		"grid_high": 192,
		"grid_low": 128,
		"peak_height": 275.0,
		"snow_line": 90.0,
		"warp_strength": 65.0,
		"ridge_amp": 36.0,
		"detail_amp": 3.0,
		"band_height": 9.0,
		"band_tread": 0.55,
		"band_rise": 0.3,
		"fog_density": 0.005,
		"sky_energy": 1.35,
		"unlock_level": 4,
		"difficulty": "Advanced",
	},
	"canyon_run": {
		"id": "canyon_run",
		"name": "Canyon Run",
		"subtitle": "Deep cut gorges and high-commitment chutes",
		"seed_value": 8192,
		"grid_high": 192,
		"grid_low": 128,
		"peak_height": 310.0,
		"snow_line": 220.0,
		"warp_strength": 110.0,
		"ridge_amp": 52.0,
		"detail_amp": 5.0,
		"band_height": 16.0,
		"band_tread": 0.35,
		"band_rise": 0.5,
		"fog_density": 0.004,
		"sky_energy": 1.0,
		"unlock_level": 6,
		"difficulty": "Expert",
	},
	"extreme_summit": {
		"id": "extreme_summit",
		"name": "Extreme Summit",
		"subtitle": "Maximum vertical drop & technical choke points",
		"seed_value": 9999,
		"grid_high": 192,
		"grid_low": 128,
		"peak_height": 340.0,
		"snow_line": 140.0,
		"warp_strength": 95.0,
		"ridge_amp": 58.0,
		"detail_amp": 6.0,
		"band_height": 18.0,
		"band_tread": 0.3,
		"band_rise": 0.55,
		"fog_density": 0.006,
		"sky_energy": 1.3,
		"unlock_level": 8,
		"difficulty": "Master",
	},
}


static func get_mountain(id: String) -> Dictionary:
	if MOUNTAINS.has(id):
		return MOUNTAINS[id]
	return MOUNTAINS["alpine_valley"]


static func get_all_ids() -> Array[String]:
	return [
		"alpine_valley",
		"rocky_ridge",
		"snow_mountain",
		"canyon_run",
		"extreme_summit",
	]


static func get_mountain_count() -> int:
	return MOUNTAINS.size()
