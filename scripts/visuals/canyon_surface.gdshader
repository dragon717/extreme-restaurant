shader_type spatial;
render_mode cull_disabled, shadows_disabled;
uniform sampler2D painted : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D relief : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm : filter_linear_mipmap, repeat_disable;
uniform sampler2D ground_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool landscape = false;
uniform vec3 season_weights = vec3(0.0);
uniform float skylight : hint_range(0.0,1.0) = 0.78;
uniform float dusk = 0.;
void fragment(){
	vec2 uv=UV;
	vec3 art=texture(painted,uv).rgb;
	float wet=0.0;
	if (landscape) {
		wet=smoothstep(.042,.125,art.b-art.r)*smoothstep(.025,.12,art.g-art.r);
		uv += wet*vec2(sin(uv.y*137.0+TIME*.81),cos(uv.x*95.0+TIME*.63))*.00055;
		art=texture(painted,uv).rgb;
		float close_detail = 1.0-smoothstep(.28,.8,length(fwidth(UV)*vec2(1585.,992.)));
		float moss=smoothstep(.0,.13,art.g-art.b)*(1.0-wet);
		vec3 fine=texture(ground_detail,uv*vec2(39.,24.)).rgb;
		art=mix(art,art*(.55+fine*2.3),close_detail*moss*.68);
	}
	float lightness=dot(art,vec3(.30,.55,.15));
	if (landscape) {
		float green=smoothstep(-.015,.095,art.g-art.b)*smoothstep(-.14,.01,art.g-art.r)*(1.-wet);
		art=mix(art,art*vec3(.86,1.12,.87),green*season_weights.x);
		art=mix(art,vec3(1.43,.84,.35)*lightness,green*season_weights.y*.85);
		float snow=smoothstep(.018,.32,lightness)*(.48+.52*green)*(1.-wet);
		art=mix(art,vec3(.65,.75,.78)*(.44+lightness*.58),snow*season_weights.z);
		art=mix(art,art*vec3(.74,.93,1.16),wet*season_weights.z*.65);
	} else {
		float ridge=smoothstep(.09,.37,lightness)*smoothstep(-.02,.16,art.r-art.b);
		art=mix(art,vec3(.72,.77,.81)*(.44+lightness*.50),ridge*season_weights.z*.57);
	}
	vec3 packed=texture(orm,uv).rgb;
	art *= mix(vec3(1.),vec3(.70,.78,.98),dusk);
	ALBEDO=art*.22;
	SPECULAR=.12;
	EMISSION=art*skylight*(1.-dusk*.21);
	ROUGHNESS=mix(packed.g,.39,wet);
	METALLIC=packed.b;
	NORMAL_MAP=texture(relief,uv).rgb;
	NORMAL_MAP_DEPTH=.44;
}
