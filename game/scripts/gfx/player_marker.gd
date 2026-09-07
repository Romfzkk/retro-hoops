class_name PlayerMarker
extends MeshInstance3D

# Ring on the floor under the player you are controlling, with the outer arc
# showing stamina. On the court rather than on the HUD, so your eyes never
# leave the play to check it.

const SIZE := 1.7
const LIFT := 0.015

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 team_colour : source_color = vec4(1.0, 0.42, 0.17, 1.0);
uniform vec4 stamina_colour : source_color = vec4(0.22, 0.84, 0.48, 1.0);
uniform float stamina = 1.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}

	// Inner ring: identity. Outer ring: stamina, drained clockwise from twelve.
	float inner = smoothstep(0.60, 0.63, r) * (1.0 - smoothstep(0.74, 0.77, r));
	float outer_band = smoothstep(0.84, 0.87, r) * (1.0 - smoothstep(0.96, 0.99, r));

	float angle = atan(p.x, -p.y);
	float turn = angle < 0.0 ? angle + 6.2831853 : angle;
	float filled = step(turn, stamina * 6.2831853);

	vec3 colour = team_colour.rgb;
	float alpha = inner * (0.85 + pulse * 0.15);
	float outer_alpha = outer_band * mix(0.10, 0.95, filled);
	colour = mix(colour, stamina_colour.rgb, outer_band * filled);
	alpha = max(alpha, outer_alpha);
	if (alpha < 0.01) {
		discard;
	}

	ALBEDO = colour;
	ALPHA = alpha;
}
"""

var _material: ShaderMaterial
var _pulse := 0.0

var target: PlayerPawn


static func create(parent: Node3D, colour: Color) -> PlayerMarker:
	var marker := PlayerMarker.new()
	marker.name = "PlayerMarker"
	var quad := QuadMesh.new()
	quad.size = Vector2(SIZE, SIZE)
	marker.mesh = quad
	marker.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shader := Shader.new()
	shader.code = SHADER
	marker._material = ShaderMaterial.new()
	marker._material.shader = shader
	marker._material.set_shader_parameter("team_colour", colour.lightened(0.25))
	marker.material_override = marker._material
	parent.add_child(marker)
	return marker


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		visible = false
		return
	visible = true
	global_position = target.global_position + Vector3(0.0, LIFT, 0.0)
	_pulse = fmod(_pulse + delta * 2.4, TAU)
	_material.set_shader_parameter("stamina", clampf(target.stamina, 0.0, 1.0))
	_material.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_pulse))
