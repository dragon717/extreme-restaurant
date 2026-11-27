shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "res://scripts/visuals/crew_surface.gdshaderinc"
uniform bool mirrored = false;
void fragment() {
	vec4 shaded=texture(paint,UV)*COLOR;
	ALBEDO=shaded.rgb;
	ALPHA=shaded.a;
	ALPHA_SCISSOR_THRESHOLD=.23;
	NORMAL_MAP=portrait_normal(UV,mirrored);
	NORMAL_MAP_DEPTH=.92;
	float trim=metal_trim(shaded.rgb);
	ROUGHNESS=mix(.87,.47,trim);
	METALLIC=trim*.42;
	SPECULAR=.27;
}
