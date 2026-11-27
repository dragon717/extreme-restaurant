shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "res://scripts/visuals/crew_surface.gdshaderinc"
#include "res://scripts/visuals/stride_pose.gdshaderinc"
void fragment() {
	vec2 at = region.xy + vec2(flipped ? 1.-UV.x : UV.x,UV.y)*region.zw;
	vec4 color = texture(paint,at);
	ALBEDO = color.rgb;
	ALPHA = color.a*opacity;
	ALPHA_SCISSOR_THRESHOLD = .23;
	NORMAL_MAP=portrait_normal(at,flipped);
	NORMAL_MAP_DEPTH=.92;
	float trim=metal_trim(color.rgb);
	ROUGHNESS=mix(.87,.47,trim);
	METALLIC=trim*.42;
	SPECULAR=.27;
}
