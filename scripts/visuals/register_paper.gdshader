shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D ink : source_color, filter_linear;
uniform sampler2D fibres : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D positions : filter_nearest, repeat_disable;
uniform bool lower_leaf = false;
uniform vec2 sheet_size = vec2(2.1632,2.7716);
vec3 sample_leaf(ivec2 index, ivec2 dims) {
	ivec2 at = clamp(index,ivec2(0),dims-ivec2(1));
	vec3 pos = texelFetch(positions,at,0).xyz;
	if (lower_leaf) {
		vec2 uv = vec2(at)/vec2(dims-ivec2(1));
		vec3 rest_position = vec3((uv-vec2(.5))*sheet_size*vec2(1.,-1.),0.);
		pos = mix(rest_position,pos,.18)+vec3(.009,-.022,-.049);
	}
	return pos;
}
void vertex() {
	ivec2 dims = textureSize(positions,0);
	ivec2 at = ivec2(round(UV*vec2(dims-ivec2(1))));
	VERTEX = sample_leaf(at,dims);
	vec3 right = sample_leaf(at+ivec2(1,0),dims)-sample_leaf(at-ivec2(1,0),dims);
	vec3 down = sample_leaf(at+ivec2(0,1),dims)-sample_leaf(at-ivec2(0,1),dims);
	NORMAL = normalize(cross(down,right));
}
void fragment() {
	vec3 paper = texture(fibres, UV).rgb;
	vec3 color = FRONT_FACING && !lower_leaf ? texture(ink,UV).rgb : paper*vec3(.91,.83,.70);
	ALBEDO = color*.72;
	EMISSION = color*.25;
	ROUGHNESS = .93;
	SPECULAR = .15;
	BACKLIGHT = paper*.12;
}
