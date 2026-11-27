shader_type canvas_item;
uniform vec2 panel_size = vec2(1.);
varying vec2 panel_uv;
void vertex() { panel_uv = VERTEX / max(vec2(1.),panel_size); }
void fragment() {
	vec4 paint = texture(TEXTURE,UV);
	float side = smoothstep(0.,.29,panel_uv.x);
	float foot = 1.-smoothstep(.53,1.,panel_uv.y);
	COLOR = vec4(paint.rgb,paint.a * side * foot * COLOR.a);
}
