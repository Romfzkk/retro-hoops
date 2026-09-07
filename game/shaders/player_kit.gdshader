shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The character's kit is painted into its texture rather than split into
// materials, so a team colour cannot be assigned - it has to be found. Skin and
// kit sit in the same warm hues and are told apart by saturation, whose
// histogram is clearly bimodal: skin peaks around 0.3-0.55, kit colour around
// 0.85-1.0, with a trough at 0.78 between them.
//
// Colour alone cannot do all of it. A shadowed forearm and a black jersey are
// both dark and near neutral, which is what speckled kit colour across the
// arms and hands, and hair is the same black as the jersey. So the texture's
// alpha carries a region baked from the rig: what the bone weights already
// know is not guessed at again. Only the trunk, where jersey, shorts and skin
// share bones, is left to the colour classifier.

uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 jersey_colour : source_color = vec3(0.11, 0.31, 0.61);
uniform vec3 trim_colour : source_color = vec3(0.95, 0.96, 0.97);
uniform vec3 skin_colour : source_color = vec3(0.29, 0.18, 0.12);
uniform float trim_saturation = 0.86;
uniform float fabric_saturation = 0.34;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.78;

float saturation_of(vec3 c) {
	float high = max(c.r, max(c.g, c.b));
	float low = min(c.r, min(c.g, c.b));
	return high > 0.0 ? (high - low) / high : 0.0;
}

// Replaces chroma but keeps the shading that carries fabric folds and muscle.
vec3 retint(vec3 target, float luma, float reference, float gain) {
	return clamp(target * clamp(0.35 + gain * (luma / reference), 0.0, 1.85), 0.0, 1.0);
}

void fragment() {
	vec4 sampled = texture(base_texture, UV);
	vec3 source = sampled.rgb;
	float high = max(source.r, max(source.g, source.b));
	float sat = saturation_of(source);
	float luma = dot(source, vec3(0.2126, 0.7152, 0.0722));

	vec3 tinted = source;
	if (sampled.a > 0.70) {
		// Trunk and legs: jersey, shorts and skin share these bones, so the
		// saturation split decides.
		if (sat > trim_saturation && high > 0.06) {
			tinted = retint(trim_colour, luma, 0.30, 0.62);
		} else if (sat < fabric_saturation && high < 0.30) {
			tinted = retint(jersey_colour, luma, 0.05, 0.72);
		} else {
			tinted = retint(skin_colour, luma, 0.16, 0.62);
		}
	} else if (sampled.a > 0.19) {
		// Arms and hands are skin whatever the shading says.
		tinted = retint(skin_colour, luma, 0.16, 0.62);
	}
	// Anything darker than that is hair, beard or scalp, and keeps its colour.

	ALBEDO = tinted;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.35;
}
