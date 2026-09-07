class_name BodyMesh
extends RefCounted

# Builds a single skinned mesh by lofting rings along the skeleton.
#
# The previous rig hung separate primitives off each joint, which is what made
# it read as parts bolted together: every segment had a visible end, and
# nothing deformed. Here the whole body is one continuous surface bound to
# bones, so an elbow bends the skin instead of rotating a detached tube.

## Vertices around each ring. Twelve left a visibly faceted silhouette on the
## torso at close range; twenty reads round and still costs very little.
const RING_SEGMENTS := 20

var _tool := SurfaceTool.new()
var _previous_ring: PackedInt32Array = PackedInt32Array()
var _vertex_count := 0


func begin() -> void:
	_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_previous_ring = PackedInt32Array()
	_vertex_count = 0


func commit() -> ArrayMesh:
	_tool.generate_normals()
	_tool.generate_tangents()
	return _tool.commit()


## Break the surface so the next chain does not tie back to the previous one.
func cut() -> void:
	_previous_ring = PackedInt32Array()


# A station is one cross-section: how far along the chain it sits, and how wide
# the body is there. This is where the shape comes from - a bicep bulge is just
# a wider station a third of the way down the upper arm.
static func station(t: float, radius: float, depth_scale: float = 1.0) -> Dictionary:
	return {"t": t, "r": radius, "depth": depth_scale}


## Lofts one limb between two bones. Vertices near the far end blend onto the
## child bone so the joint creases instead of shearing.
func chain(from: Vector3, to: Vector3, bone_a: int, bone_b: int,
		stations: Array, blend_start: float = 0.62, twist: float = 0.0) -> void:
	for entry in stations:
		var t: float = entry["t"]
		var centre := from.lerp(to, t)
		var weight_b := 0.0
		if bone_b >= 0 and t > blend_start:
			weight_b = smoothstep(blend_start, 1.0, t) * 0.5
		_ring(centre, float(entry["r"]), float(entry["depth"]), bone_a, bone_b,
			weight_b, t, twist)


## A closed dome, used to cap a chain (the top of the head, the end of a limb).
func cap(centre: Vector3, radius: float, depth_scale: float, bone: int,
		up: float) -> void:
	const RINGS := 3
	for i in range(1, RINGS + 1):
		var angle := (float(i) / float(RINGS)) * PI * 0.5
		var ring_radius := radius * cos(angle)
		var offset := up * radius * sin(angle)
		_ring(centre + Vector3(0.0, offset, 0.0), ring_radius, depth_scale,
			bone, -1, 0.0, 1.0, 0.0)


func _ring(centre: Vector3, radius: float, depth_scale: float, bone_a: int,
		bone_b: int, weight_b: float, v: float, twist: float) -> void:
	var indices := PackedInt32Array()
	var bones := PackedInt32Array([maxi(bone_a, 0), maxi(bone_b, 0), 0, 0])
	var weights := PackedFloat32Array([1.0 - weight_b, weight_b, 0.0, 0.0])
	if bone_b < 0:
		bones = PackedInt32Array([maxi(bone_a, 0), 0, 0, 0])
		weights = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])

	for i in RING_SEGMENTS:
		var angle := TAU * float(i) / float(RING_SEGMENTS) + twist
		var offset := Vector3(sin(angle) * radius, 0.0,
			cos(angle) * radius * depth_scale)
		_tool.set_uv(Vector2(float(i) / float(RING_SEGMENTS), v))
		_tool.set_bones(bones)
		_tool.set_weights(weights)
		_tool.add_vertex(centre + offset)
		indices.append(_vertex_count)
		_vertex_count += 1

	if not _previous_ring.is_empty():
		for i in RING_SEGMENTS:
			var next := (i + 1) % RING_SEGMENTS
			var a := _previous_ring[i]
			var b := _previous_ring[next]
			var c := indices[next]
			var d := indices[i]
			_tool.add_index(a)
			_tool.add_index(b)
			_tool.add_index(c)
			_tool.add_index(a)
			_tool.add_index(c)
			_tool.add_index(d)
	_previous_ring = indices


## An ellipsoid rigidly bound to one bone, for the head and the shoes.
func blob(centre: Vector3, radius: Vector3, bone: int, rings: int = 8) -> void:
	cut()
	var first := true
	for ring in range(rings + 1):
		var phi := PI * float(ring) / float(rings)
		var y := cos(phi)
		var scale := sin(phi)
		var indices := PackedInt32Array()
		for i in RING_SEGMENTS:
			var angle := TAU * float(i) / float(RING_SEGMENTS)
			var offset := Vector3(sin(angle) * radius.x * scale, y * radius.y,
				cos(angle) * radius.z * scale)
			_tool.set_uv(Vector2(float(i) / float(RING_SEGMENTS),
				float(ring) / float(rings)))
			_tool.set_bones(PackedInt32Array([maxi(bone, 0), 0, 0, 0]))
			_tool.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
			_tool.add_vertex(centre + offset)
			indices.append(_vertex_count)
			_vertex_count += 1
		if not first:
			for i in RING_SEGMENTS:
				var next := (i + 1) % RING_SEGMENTS
				_tool.add_index(_previous_ring[i])
				_tool.add_index(_previous_ring[next])
				_tool.add_index(indices[next])
				_tool.add_index(_previous_ring[i])
				_tool.add_index(indices[next])
				_tool.add_index(indices[i])
		first = false
		_previous_ring = indices
	cut()
