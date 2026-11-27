shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	float distance_from_foot=length((UV-.5)*2.);
	if(distance_from_foot>=1.) discard;
	ALBEDO=vec3(.065,.082,.087);
	ALPHA=.33*(1.-smoothstep(.06,1.,distance_from_foot));
}
