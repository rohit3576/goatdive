extends Node
## TEMP smoke helper (deleted with the phase): physics-side driver for
## trick injection. The idle/physics fork makes Input presses and
## mid-air idle calls unreliable (engine quirk, documented in the
## completion doc); script-state reads cross worlds fine — so this node
## does, per PHYSICS tick, what a real player's keyboard/mouse do:
## rotate the parent (mouse-spin channel) and fire a buffered flip at
## the detector's window open.
var rate := 0.0
var ticks := 0


func _physics_process(d: float) -> void:
	ticks += 1
	var parent := get_parent()
	if parent == null:
		return
	parent.rotation.y += rate * d
	if get_meta("arm_flip", false):
		var det: Node = (parent as Node).get_node_or_null("TrickDetector")
		if det != null and bool((det.call("get_debug_state") as Dictionary)["air"]):
			det.call("_begin_flip", "front")
			set_meta("arm_flip", false)
