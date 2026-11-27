shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D character : source_color, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
void fragment(){
	float mask=texture(character,UV).a;
	float depth=texture(scene_depth,SCREEN_UV).r;
	// Reverse-Z. An opaque surface closer than this character owns the pixel.
	if(mask<.48 || depth<=FRAGCOORD.z+.00012){discard;}
	ALBEDO=vec3(.38,.82,.79);
	ALPHA=.42;
}
