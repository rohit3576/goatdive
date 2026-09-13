extends Node
## Static horn mesh builder (Phase 2, decision D5): a tapering circular sweep
## along a quadratic Bézier curving up-and-back. Zero assets, instantly tunable.

static func build(
	length: float = 0.35, curvature: float = 0.5, rings: int = 12, segs: int = 8
) -> ArrayMesh:
	var bend := curvature * length
	var p0 := Vector3(0.0, 0.0, 0.0)
	var p1 := Vector3(0.0, length, bend * 0.2)
	var p2 := Vector3(0.0, length * 0.8, bend)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for r in rings + 1:
		var t := float(r) / float(rings)
		var center := _bezier(p0, p1, p2, t)
		var tangent := (
			_bezier(p0, p1, p2, minf(t + 0.01, 1.0)) - center
		).normalized()
		# Ring plane frame: X projected off the tangent, then the cross.
		var side := (Vector3.RIGHT - tangent * Vector3.RIGHT.dot(tangent)).normalized()
		var up := tangent.cross(side).normalized()
		var radius := lerpf(0.055, 0.012, t)
		for s in segs:
			var ang := TAU * float(s) / float(segs)
			st.add_vertex(center + side * (cos(ang) * radius) + up * (sin(ang) * radius))

	for r in rings:
		for s in segs:
			var s2 := (s + 1) % segs
			var a := r * segs + s
			var b := r * segs + s2
			var c := (r + 1) * segs + s
			var d := (r + 1) * segs + s2
			# Godot front faces are CW from the front — (a,c,b)/(b,c,d)
			# points the horn surface outward.
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)

	st.generate_normals()
	return st.commit()


static func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var q0 := p0.lerp(p1, t)
	var q1 := p1.lerp(p2, t)
	return q0.lerp(q1, t)
