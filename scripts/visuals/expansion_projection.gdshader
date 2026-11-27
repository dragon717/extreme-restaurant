shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D surface_paint : source_color, hint_default_white, repeat_enable, filter_linear_mipmap;
uniform vec4 accent : source_color = vec4(.51, .78, .80, 1.);
uniform bool footprint = false;
uniform bool available = false;
uniform bool highlighted = false;
uniform vec2 span = vec2(1.);

void fragment() {
	float strength = float(highlighted) * .09;
	float pulse = available ? .5 + .5 * sin(TIME * 1.8) : 0.;
	if (footprint) {
		vec2 to_edge = min(UV, 1. - UV) * span;
		float edge = min(to_edge.x, to_edge.y);
		float corner = 1. - smoothstep(.35, .8, max(to_edge.x, to_edge.y));
		float feather = max(fwidth(edge), .014);
		float rim = 1. - smoothstep(.045, .045 + feather, edge);
		float halo = 1. - smoothstep(0., .38, edge);
		float grain = dot(texture(surface_paint, UV * span * .53).rgb, vec3(.30,.58,.12));
		ALBEDO = accent.rgb * (.58 + .52 * grain + .38 * rim + .33 * corner);
		ALPHA = .12 + .14 * grain + .10 * halo + rim * (.36 + corner * .22) + strength + .055 * pulse;
	} else {
		float grain = dot(texture(surface_paint, UV).rgb, vec3(.30,.58,.12));
		float edge = pow(1. - abs(dot(normalize(NORMAL),normalize(VIEW))), 2.);
		ALBEDO = accent.rgb * (.48 + 1.25 * grain + .33 * edge);
		ALPHA = .20 + .18 * grain + .15 * edge + strength + .045 * pulse;
	}
}
