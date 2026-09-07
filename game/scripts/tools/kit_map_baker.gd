extends SceneTree

# Bakes the player texture's alpha channel into a region map, so the kit shader
# knows what it is looking at instead of guessing from colour alone.
#
# Colour cannot separate a shadowed forearm from a black jersey: both are dark
# and close to neutral, which is why kit colour used to speckle across the arms
# and hands. The rig can, though. Every vertex carries bone weights, so the
# dominant bone says whether a texel is skin, hair or something that has to be
# decided by colour because the jersey and shorts share those bones.
#
# godot --headless --path game -s res://scripts/tools/kit_map_baker.gd

const SOURCE := "res://art/player.fbx"
const TEXTURE := "res://art/player_0.png"
const OUTPUT := "res://art/player_kit.png"
const SIZE := 2048
## Edge slack when filling a triangle, so seams between UV islands are covered.
const EDGE_SLACK := -0.12

# Alpha is the region. Nothing between these is meaningful; the shader compares
# against midpoints.
const REGION_PROTECT := 0
const REGION_SKIN := 96
const REGION_DECIDE := 255

const SKIN_BONES := ["LeftArm", "LeftForeArm", "LeftHand",
	"RightArm", "RightForeArm", "RightHand"]
const PROTECT_BONES := ["Head", "HeadTop_End", "Neck"]


func _init() -> void:
	var scene := ResourceLoader.load(SOURCE) as PackedScene
	if scene == null:
		push_error("Cannot load %s" % SOURCE)
		quit(1)
		return
	var root := scene.instantiate()
	var skeleton: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var instance: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]

	var regions := _bone_regions(skeleton, instance)
	var map := Image.create(SIZE, SIZE, false, Image.FORMAT_R8)
	map.fill(Color8(REGION_DECIDE, 0, 0))
	var painted := _paint(map, instance.mesh, regions)

	var base := ResourceLoader.load(TEXTURE) as Texture2D
	if base == null:
		push_error("Cannot load %s" % TEXTURE)
		quit(1)
		return
	var out := base.get_image()
	out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	if out.get_width() != SIZE:
		map.resize(out.get_width(), out.get_height(), Image.INTERPOLATE_NEAREST)
	for y in out.get_height():
		for x in out.get_width():
			var colour := out.get_pixel(x, y)
			colour.a = map.get_pixel(x, y).r
			out.set_pixel(x, y, colour)
	var path := ProjectSettings.globalize_path(OUTPUT)
	var err := out.save_png(path)
	if err != OK:
		push_error("Could not write %s: %s" % [path, error_string(err)])
		quit(1)
		return
	print("wrote %s  (%d triangles painted, %d bones mapped)"
		% [OUTPUT, painted, regions.size()])
	quit()


## Keyed by the index a vertex actually stores, which is a position in the
## mesh's skin rather than in the skeleton. Confusing the two silently paints
## the map onto the wrong body parts.
func _bone_regions(skeleton: Skeleton3D, instance: MeshInstance3D) -> Dictionary:
	var regions := {}
	var skin := instance.skin
	var binds := skin.get_bind_count() if skin != null else skeleton.get_bone_count()
	for bind in binds:
		var bone_name := ""
		if skin != null:
			bone_name = skin.get_bind_name(bind)
			if bone_name.is_empty():
				var bone := skin.get_bind_bone(bind)
				if bone >= 0:
					bone_name = skeleton.get_bone_name(bone)
		else:
			bone_name = skeleton.get_bone_name(bind)
		bone_name = bone_name.replace("mixamorig_", "").replace("mixamorig:", "")
		if PROTECT_BONES.has(bone_name):
			regions[bind] = REGION_PROTECT
		elif SKIN_BONES.has(bone_name):
			regions[bind] = REGION_SKIN
	return regions


func _paint(map: Image, mesh: Mesh, regions: Dictionary) -> int:
	var painted := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if uvs.is_empty() or bones.is_empty():
			continue
		var per_vertex := bones.size() / uvs.size()
		for i in range(0, indices.size(), 3):
			var region := _triangle_region(indices, i, bones, weights, per_vertex, regions)
			if region == REGION_DECIDE:
				continue
			_fill(map, uvs[indices[i]], uvs[indices[i + 1]], uvs[indices[i + 2]], region)
			painted += 1
	return painted


## A triangle takes a region only when every corner agrees, so the boundary
## between a sleeve and an arm is left to the colour classifier.
func _triangle_region(indices: PackedInt32Array, at: int, bones: PackedInt32Array,
		weights: PackedFloat32Array, per_vertex: int, regions: Dictionary) -> int:
	var agreed := -1
	for corner in 3:
		var vertex := indices[at + corner]
		var best_weight := 0.0
		var best_bone := -1
		for slot in per_vertex:
			var weight := weights[vertex * per_vertex + slot]
			if weight > best_weight:
				best_weight = weight
				best_bone = bones[vertex * per_vertex + slot]
		if not regions.has(best_bone):
			return REGION_DECIDE
		var region: int = regions[best_bone]
		if agreed >= 0 and region != agreed:
			return REGION_DECIDE
		agreed = region
	return agreed


func _fill(map: Image, a: Vector2, b: Vector2, c: Vector2, region: int) -> void:
	var pa := Vector2(a.x, a.y) * float(SIZE)
	var pb := Vector2(b.x, b.y) * float(SIZE)
	var pc := Vector2(c.x, c.y) * float(SIZE)
	var low := Vector2i(pa.min(pb).min(pc).floor()) - Vector2i(2, 2)
	var high := Vector2i(pa.max(pb).max(pc).ceil()) + Vector2i(2, 2)
	low = low.clamp(Vector2i.ZERO, Vector2i(SIZE - 1, SIZE - 1))
	high = high.clamp(Vector2i.ZERO, Vector2i(SIZE - 1, SIZE - 1))
	var area := (pb.y - pc.y) * (pa.x - pc.x) + (pc.x - pb.x) * (pa.y - pc.y)
	var shade := Color8(region, 0, 0)
	if absf(area) < 0.0001:
		return
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var w0 := ((pb.y - pc.y) * (float(x) - pc.x)
				+ (pc.x - pb.x) * (float(y) - pc.y)) / area
			var w1 := ((pc.y - pa.y) * (float(x) - pc.x)
				+ (pa.x - pc.x) * (float(y) - pc.y)) / area
			if w0 > EDGE_SLACK and w1 > EDGE_SLACK and (1.0 - w0 - w1) > EDGE_SLACK:
				map.set_pixel(x, y, shade)
