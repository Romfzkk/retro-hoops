shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The kit is painted into the character's texture, so a team colour cannot be
// assigned - it has to be found. That decision is made once, offline, and
// stored in the texture's alpha as a region: hair, skin, fabric or trim. The
// shader only retints what it is told.
//
// It used to classify by colour here, which tied the whole thing to one
// model's palette. The first character had a black jersey, so dark meant
// fabric; the second has a pale one, and the same rule painted the jersey in
// the player's own complexion. The regions are measured against the arms,
// which the rig identifies as skin with certainty, so nothing assumes a palette
// any more.

uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 jersey_colour : source_color = vec3(0.11, 0.31, 0.61);
uniform vec3 trim_colour : source_color = vec3(0.95, 0.96, 0.97);
uniform vec3 skin_colour : source_color = vec3(0.29, 0.18, 0.12);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.78;

// Replaces chroma but keeps the shading that carries fabric folds and muscle.
vec3 retint(vec3 target, float luma, float reference, float gain) {
	return clamp(target * clamp(0.35 + gain * (luma / reference), 0.0, 1.85), 0.0, 1.0);
}

void fragment() {
	vec4 sampled = texture(base_texture, UV);
	vec3 source = sampled.rgb;
	float luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
	float region = sampled.a;

	vec3 tinted = source;
	if (region < 0.16) {
		// Hair, beard and scalp keep whatever colour they were given.
	} else if (region < 0.47) {
		tinted = retint(skin_colour, luma, 0.30, 0.62);
	} else if (region < 0.78) {
		tinted = retint(jersey_colour, luma, 0.22, 0.72);
	} else {
		tinted = retint(trim_colour, luma, 0.30, 0.62);
	}

	ALBEDO = tinted;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.35;
}
