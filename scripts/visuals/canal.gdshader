shader_type spatial;
render_mode cull_disabled;
void fragment() {
	float flow = sin(UV.y * 180.0 + TIME * 1.8 + sin(UV.x * 7.0) * 1.5);
	float fine = sin(UV.y * 520.0 - TIME * 3.1 + UV.x * 11.0) * 0.5;
	float edge = smoothstep(0.37, 0.49, abs(UV.x - 0.5));
	float fleck = smoothstep(0.8, 1.2, flow + fine) * (1.0 - 0.7 * edge);
	ALBEDO = mix(vec3(0.06, 0.20, 0.24), vec3(0.24, 0.48, 0.46), fleck);
	ROUGHNESS = 0.39;
	SPECULAR = 0.57;
}
