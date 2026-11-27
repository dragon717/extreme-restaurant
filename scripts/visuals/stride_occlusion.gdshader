shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D paint : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
#include "res://scripts/visuals/stride_pose.gdshaderinc"
void fragment() {
	vec2 at=region.xy+vec2(flipped ? 1.-UV.x : UV.x,UV.y)*region.zw;
	if(texture(paint,at).a<.48 || texture(scene_depth,SCREEN_UV).r<=FRAGCOORD.z+.00012){discard;}
	ALBEDO=vec3(.38,.82,.79);
	ALPHA=.42*opacity;
}
