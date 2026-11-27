shader_type spatial;
render_mode cull_disabled;
uniform sampler2D paint : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D relief : hint_normal, filter_linear_mipmap, repeat_disable;
#include "res://scripts/visuals/stride_pose.gdshaderinc"
void fragment() {
	vec2 at = region.xy + vec2(flipped ? 1.-UV.x : UV.x,UV.y)*region.zw;
	vec4 color = texture(paint,at);
	ALBEDO = color.rgb;
	ALPHA = color.a*opacity;
	ALPHA_SCISSOR_THRESHOLD = .23;
	NORMAL_MAP = texture(relief,at).rgb;
	NORMAL_MAP_DEPTH = .52;
	ROUGHNESS = .84;
}
