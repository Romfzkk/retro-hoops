extends SceneTree

# Bakes the player texture's alpha into a region map, so the kit shader knows
# what it is looking at instead of guessing from colour.
#
# Colour cannot do this. The first character had a black jersey, so dark meant
# fabric. The second has a pale one in almost exactly its wearer's complexion,
# and the same rule painted the shirt in skin. There is no threshold that
# survives both, because the two things are not reliably different colours.
#
# The rig is different. Every vertex carries bone weights, and a vertex on the
# chest is on the chest whatever colour it was painted. So the map is built from
# the skeleton alone: sleeves and shorts follow the bones they hang on, and the
# only judgement left is where a hem sits along a limb.
#
# godot --headless --path game -s res://scripts/tools/kit_map_baker.gd

const SOURCE := "res://art/player.fbx"
const TEXTURE := "res://art/player_0.png"
const OUTPUT := "res://art/player_kit.png"
const SIZE := 2048
## Edge slack when filling a triangle, so seams between UV islands are covered.
const EDGE_SLACK := -0.12

# Alpha carries the region. The shader compares against the midpoints, so these
# only have to stay ordered and far apart.
const REGION_PROTECT := 0
const REGION_SKIN := 80
const REGION_KIT := 160
const REGION_TRIM := 240

## Hair, face and neck keep whatever they were painted.
const PROTECT_BONES := ["Head", "HeadTop_End", "Neck"]
## Bare arms below a sleeveless jersey, and shins below the shorts.
const SKIN_BONES := ["LeftArm", "LeftForeArm", "LeftHand",
	"RightArm", "RightForeArm", "RightHand", "LeftLeg", "RightLeg"]
## The shirt and what it hangs from.
const KIT_BONES := ["Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder"]
## Shoes take the trim colour, which is what makes a kit read as a kit.
const TRIM_BONES := ["LeftFoot", "LeftToeBase", "LeftToe_End",
	"RightFoot", "RightToeBase", "RightToe_End"]
## Thighs are half shorts and half leg. Measured from the hip down, this is
## where the hem falls.
const SHORTS_HEM := 0.58
const THIGH_BONES := {"LeftUpLeg": "LeftLeg", "RightUpLeg": "RightLeg"}
## The hips are under the shorts.
const HIP_BONES := ["Hips"]


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
	var thighs := _thigh_spans(skeleton, instance)
	var map := Image.create(SIZE, SIZE, false, Image.FORMAT_R8)
	map.fill(Color8(REGION_SKIN, 0, 0))
	var painted := _paint(map, instance.mesh, regions, thighs)

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
	print("wrote %s  (%d triangles placed, %d bones mapped)"
		% [OUTPUT, painted, regions.size()])
	quit()


## Keyed by the index a vertex actually stores, which is a position in the
## mesh's skin rather than in the skeleton. Confusing the two silently paints
## the map onto the wrong body parts.
func _bone_regions(skeleton: Skeleton3D, instance: MeshInstance3D) -> Dictionary:
	var regions := {}
	for bind in _bind_count(skeleton, instance):
		var bone_name := _bind_name(skeleton, instance, bind)
		if PROTECT_BONES.has(bone_name):
			regions[bind] = REGION_PROTECT
		elif SKIN_BONES.has(bone_name):
			regions[bind] = REGION_SKIN
		elif KIT_BONES.has(bone_name) or HIP_BONES.has(bone_name):
			regions[bind] = REGION_KIT
		elif TRIM_BONES.has(bone_name):
			regions[bind] = REGION_TRIM
	return regions


## Hip and knee positions for each thigh, so a vertex can be placed along it and
## the shorts hem found without anybody naming a colour.
func _thigh_spans(skeleton: Skeleton3D, instance: MeshInstance3D) -> Dictionary:
	var spans := {}
	for bind in _bind_count(skeleton, instance):
		var bone_name := _bind_name(skeleton, instance, bind)
		if not THIGH_BONES.has(bone_name):
			continue
		var hip := skeleton.find_bone("mixamorig_" + bone_name)
		var knee := skeleton.find_bone("mixamorig_" + THIGH_BONES[bone_name])
		if hip < 0 or knee < 0:
			continue
		spans[bind] = [skeleton.get_bone_global_rest(hip).origin,
			skeleton.get_bone_global_rest(knee).origin]
	return spans


func _bind_count(skeleton: Skeleton3D, instance: MeshInstance3D) -> int:
	return instance.skin.get_bind_count() if instance.skin != null \
		else skeleton.get_bone_count()


func _bind_name(skeleton: Skeleton3D, instance: MeshInstance3D, bind: int) -> String:
	var bone_name := ""
	if instance.skin != null:
		bone_name = instance.skin.get_bind_name(bind)
		if bone_name.is_empty():
			var bone := instance.skin.get_bind_bone(bind)
			if bone >= 0:
				bone_name = skeleton.get_bone_name(bone)
	else:
		bone_name = skeleton.get_bone_name(bind)
	return bone_name.replace("mixamorig_", "").replace("mixamorig:", "")


func _paint(map: Image, mesh: Mesh, regions: Dictionary, thighs: Dictionary) -> int:
	var painted := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if uvs.is_empty() or bones.is_empty():
			continue
		var per_vertex := bones.size() / uvs.size()
		for i in range(0, indices.size(), 3):
			var region := _triangle_region(indices, i, vertices, bones, weights,
				per_vertex, regions, thighs)
			_fill(map, uvs[indices[i]], uvs[indices[i + 1]], uvs[indices[i + 2]], region)
			painted += 1
	return painted


## A triangle takes the region of the bone that moves it most. Where every
## corner disagrees the majority wins, so a seam between a sleeve and an arm
## lands on one side rather than being left undecided.
func _triangle_region(indices: PackedInt32Array, at: int, vertices: PackedVector3Array,
		bones: PackedInt32Array, weights: PackedFloat32Array, per_vertex: int,
		regions: Dictionary, thighs: Dictionary) -> int:
	var tally := {}
	for corner in 3:
		var vertex := indices[at + corner]
		var best_weight := 0.0
		var best_bone := -1
		for slot in per_vertex:
			var weight := weights[vertex * per_vertex + slot]
			if weight > best_weight:
				best_weight = weight
				best_bone = bones[vertex * per_vertex + slot]
		var region := REGION_SKIN
		if thighs.has(best_bone):
			region = _thigh_region(vertices[vertex], thighs[best_bone])
		elif regions.has(best_bone):
			region = regions[best_bone]
		tally[region] = int(tally.get(region, 0)) + 1
	var winner := REGION_SKIN
	var best_count := 0
	for region in tally:
		if int(tally[region]) > best_count:
			best_count = int(tally[region])
			winner = int(region)
	return winner


## Shorts above the hem, bare leg below it.
func _thigh_region(vertex: Vector3, span: Array) -> int:
	var hip: Vector3 = span[0]
	var knee: Vector3 = span[1]
	var axis := knee - hip
	var length_squared := axis.length_squared()
	if length_squared < 0.000001:
		return REGION_KIT
	var along := clampf((vertex - hip).dot(axis) / length_squared, 0.0, 1.0)
	return REGION_KIT if along < SHORTS_HEM else REGION_SKIN


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
