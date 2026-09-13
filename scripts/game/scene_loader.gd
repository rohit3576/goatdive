extends Node
## Scene loader stub — swaps the World child of a parent node.
## Phase 6 replaces this with the full scene-flow manager (countdown, results, menus).
##
## Not an autoload: callers preload this script and use the static function,
## so it works without the global class cache.

static func switch(world_parent: Node, scene_path: String) -> Node:
	for child in world_parent.get_children():
		child.queue_free()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("SceneLoader: failed to load scene: %s" % scene_path)
		return null
	var instance := packed.instantiate()
	world_parent.add_child(instance)
	return instance
