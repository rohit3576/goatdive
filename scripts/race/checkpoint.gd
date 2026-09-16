class_name Checkpoint
extends Node3D
## Phase 6 race gate (plan: docs/plans/phase-6-race-system.md D2/D10):
## procedural posts + crossbar, Area3D volume trigger, state materials.
## The gate NEVER decides order — it reports bodies; RaceManager owns the
## sequence. Only the NEXT gate monitors (skipped gates physically cannot
## fire), and the manager still double-checks identity (belt + suspenders).

enum State { AHEAD, NEXT, PASSED }

signal body_entered_gate(body: Node3D)

const POST_HEIGHT := 4.0
const TRIGGER_HEIGHT := 8.0  # jump-over-able at racing speed (D2)
# Capture volume = racing-style crossing SLAB, not a needle's eye: the
# posts stay 10 m apart visually, but the trigger is wide and deep so a
# goat crossing the gate line at 20 m/s on a sloppy line still counts.
# (Phase 7 lesson: 3 m deep × 14 m wide box = 0/7 gate passes for four
# goats running the whole course — nobody could ever finish.)
const TRIGGER_DEPTH := 25.0
const TRIGGER_SIDE_MARGIN := 14.0

var idx := 0
var is_finish := false

var _forward := Vector3.FORWARD
var _mesh_inst: MeshInstance3D
var _area: Area3D

# Shared state materials (D10: ~12 gates must not cost 48 materials).
static var _state_mats: Dictionary = {}


func setup(gate_idx: int, finish: bool, forward: Vector3) -> void:
	idx = gate_idx
	is_finish = finish
	_forward = forward.normalized()
	var width := Config.RACE_GATE_WIDTH * (1.6 if finish else 1.0)
	_build_mesh(width)
	_build_trigger(width)
	set_state(State.AHEAD)


## Facing along the course (respawn transforms look this way).
func forward() -> Vector3:
	return _forward


## Visual state only (Phase 7: arming is separate — with four racers at
## different gates, every gate must monitor during RACING; the MANAGER
## owns order via per-racer gate indices).
func set_state(s: State) -> void:
	if _mesh_inst != null:
		_mesh_inst.material_override = _mat_for(s)


## Collision arming (monitoring), deferred — flips arrive inside
## body_entered callbacks where the physics server blocks direct writes.
func set_armed(armed: bool) -> void:
	if _area != null:
		_area.set_deferred("monitoring", armed)


func _build_mesh(width: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var post := CylinderMesh.new()
	post.top_radius = 0.10
	post.bottom_radius = 0.18
	post.height = POST_HEIGHT
	var half := width * 0.5
	st.append_from(post, 0, Transform3D(Basis.IDENTITY, Vector3(-half, POST_HEIGHT * 0.5, 0.0)))
	st.append_from(post, 0, Transform3D(Basis.IDENTITY, Vector3(half, POST_HEIGHT * 0.5, 0.0)))
	var bar := BoxMesh.new()
	bar.size = Vector3(width + 0.6, 0.35, 0.35)
	st.append_from(bar, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, POST_HEIGHT + 0.1, 0.0)))
	if is_finish:
		# Banner card standing on the crossbar (PlaneMesh faces +Y — stand it up).
		var banner := PlaneMesh.new()
		banner.size = Vector2(width, 1.4)
		var up := Basis(Vector3.RIGHT, PI * 0.5)
		st.append_from(banner, 0, Transform3D(up, Vector3(0.0, POST_HEIGHT - 0.8, 0.0)))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	add_child(mi)
	_mesh_inst = mi


func _build_trigger(width: float) -> void:
	var area := Area3D.new()
	area.monitoring = false  # disarmed at birth — the manager arms at GO
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width + TRIGGER_SIDE_MARGIN, TRIGGER_HEIGHT, TRIGGER_DEPTH)
	box.shape = shape
	area.add_child(box)
	area.position = Vector3(0.0, TRIGGER_HEIGHT * 0.5, 0.0)
	area.body_entered.connect(_on_body_entered)
	add_child(area)
	_area = area


func _on_body_entered(body: Node3D) -> void:
	body_entered_gate.emit(body)


func _mat_for(s: State) -> Material:
	# Shared cache (D10), per-instance selection — finish gates glow white
	# when current: the finish must read as THE destination.
	if _state_mats.is_empty():
		var ahead := StandardMaterial3D.new()
		ahead.albedo_color = Color(0.35, 0.38, 0.44)
		ahead.roughness = 1.0
		var next := StandardMaterial3D.new()
		next.albedo_color = Color(1.0, 0.62, 0.12)
		next.emission_enabled = true
		next.emission = Color(1.0, 0.5, 0.1)
		next.emission_energy_multiplier = 1.2
		var passed := StandardMaterial3D.new()
		passed.albedo_color = Color(0.16, 0.16, 0.18)
		passed.roughness = 1.0
		var finish_next := StandardMaterial3D.new()
		finish_next.albedo_color = Color(0.95, 0.95, 0.95)
		finish_next.emission_enabled = true
		finish_next.emission = Color(0.9, 0.9, 0.9)
		finish_next.emission_energy_multiplier = 0.8
		_state_mats = {
			State.AHEAD: ahead,
			State.NEXT: next,
			State.PASSED: passed,
			"finish_next": finish_next,
		}
	if s == State.NEXT and is_finish:
		return _state_mats["finish_next"]
	return _state_mats[s]
