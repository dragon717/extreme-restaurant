// The sampled normals include the rounded form of the silhouette and small
// painted folds. Mirroring the art reverses the tangent-X component as well.
uniform sampler2D paint : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D relief : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float armour = 0.0;
vec3 portrait_normal(vec2 at,bool mirrored) {
	vec2 xy = texture(relief,at).rg*2.-1.;
	vec3 normal = vec3(xy,sqrt(max(0.,1.-dot(xy,xy))));
	if(mirrored) normal.x = -normal.x;
	normal.y += .24*max(0.,normal.z);
	return normalize(normal)*.5+.5;
}
float metal_trim(vec3 color) {
	float spread = max(max(color.r,color.g),color.b)-min(min(color.r,color.g),color.b);
	return armour*(1.-smoothstep(.05,.22,spread))*smoothstep(.12,.45,dot(color,vec3(.27,.58,.15)));
}
