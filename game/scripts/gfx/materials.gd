class_name Materials
extends RefCounted

# Shared material factory. Keeping them in one place is what stops the arena
# from drifting into ten slightly different shades of orange.

static func flat(colour: Color, roughness: float = 0.85,
		metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = metallic
	return m


static func unshaded(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func emissive(colour: Color, energy: float = 1.4) -> StandardMaterial3D:
	var m := flat(colour, 0.4)
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = energy
	return m


static func glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.82, 0.88, 0.22)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func floor_material(texture: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.roughness = 0.28
	m.metallic = 0.0
	# The polished boards should catch the arena lights without turning mirror.
	m.metallic_specular = 0.65
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func skin(tone_index: int) -> StandardMaterial3D:
	const TONES := [
		Color(0.96, 0.79, 0.67), Color(0.88, 0.68, 0.53), Color(0.76, 0.55, 0.40),
		Color(0.60, 0.41, 0.29), Color(0.45, 0.30, 0.21), Color(0.33, 0.22, 0.16),
	]
	var tone: Color = TONES[clampi(tone_index, 0, TONES.size() - 1)]
	var m := flat(tone, 0.58)
	# Subsurface keeps darker tones from going flat black under arena lights.
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.28
	m.subsurf_scatter_skin_mode = true
	m.metallic_specular = 0.42
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.55
	return m


static func ball_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.83, 0.42, 0.14)
	m.roughness = 0.78
	return m
