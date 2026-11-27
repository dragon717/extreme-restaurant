shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float intensity : hint_range(0.0, 1.0) = 0.45;
uniform vec4 sheltered[8];
uniform int room_count = 0;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float altitude = world_position.y;
	if (altitude < 0.06) { discard; }
	if (altitude < 4.15) {
		for (int i=0; i<room_count; i++) {
			vec4 room = sheltered[i];
			if (all(greaterThanEqual(world_position.xz,room.xy)) && all(lessThan(world_position.xz,room.zw))) { discard; }
		}
	}
	ALBEDO = vec3(0.58, 0.73, 0.93);
	ALPHA = intensity * (1.0 - smoothstep(9.0, 15.0, altitude)) * (1.0 - abs(UV.y - 0.5) * 1.5);
}
