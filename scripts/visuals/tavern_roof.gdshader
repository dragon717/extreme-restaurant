shader_type spatial;
render_mode cull_disabled;
uniform vec4 pigment : source_color = vec4(1.0);
uniform sampler2D grain : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D relief : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float coverage = 1.0;
uniform float surface_roughness = 0.8;
uniform float metal = 0.0;
uniform vec3 season_weights = vec3(0.0);
uniform bool is_roof = false;
uniform bool leadlight = false;
uniform bool mature = false;
varying vec2 plan;
void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX,1.)).xyz;
	plan = vec2(p.x,p.z/1.2018504);
}
void fragment() {
	// Stable screen-door cutaway retains depth and shadow casting on opaque tiles.
	float threshold = fract(dot(floor(FRAGCOORD.xy), vec2(.75487767, .56984029)));
	if (coverage <= threshold) { discard; }
	vec3 art = texture(grain, UV).rgb;
	if (is_roof) {
		float ridge = (mature ? 6.65 : 6.)-(plan.x-6.)*.24;
		float porch = (mature ? 9.8 : 7.35)+(plan.y-11.)*.15;
		float v = abs(plan.y-ridge);
		float w = abs(plan.x-porch);
		float main_height = (mature ? 6.5 : 5.35)*pow(max(0.,1.-v/(mature ? 7.7 : 6.25)),1.4);
		float porch_height = (mature ? 4.5 : 3.9)*pow(max(0.,1.-w/4.35),1.37)*smoothstep(6.5,11.7,plan.y)*(1.-smoothstep(15.,18.,plan.y));
		vec2 main_uv = vec2((plan.x-.24*plan.y)*.30,v*.46);
		vec2 porch_uv = vec2((plan.y+.15*plan.x)*.30,w*.46);
		art = mix(texture(grain,main_uv).rgb,texture(grain,porch_uv).rgb,smoothstep(-.1,.25,porch_height-main_height)*smoothstep(.1,.5,porch_height));
	}
	ALBEDO = pigment.rgb * art;
	ALBEDO = mix(ALBEDO, vec3(.65,.74,.78),season_weights.z * smoothstep(.09,.48, dot(ALBEDO,vec3(.42,.45,.13))) * .81);
	EMISSION = ALBEDO * .17;
	if (leadlight) { EMISSION += ALBEDO*smoothstep(.13,.54,art.r-art.b)*smoothstep(.12,.46,art.g)*.51; }
	NORMAL_MAP = texture(relief, UV).rgb;
	NORMAL_MAP_DEPTH = .45;
	ROUGHNESS = surface_roughness;
	METALLIC = metal;
}
