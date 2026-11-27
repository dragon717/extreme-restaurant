uniform vec4 region;
uniform vec2 extent;
uniform vec2 sole;
uniform vec3 planted_shift;
uniform bool flipped;
uniform float opacity = 1.;
void vertex() {
	float foot = flipped ? 1.-sole.x : sole.x;
	// The torso follows the path. The loaded leg stays on its previous contact
	// point until weight transfers; the other leg is free to take the next step.
	float leg = smoothstep(sole.y-.35,sole.y-.035,UV.y)*(1.-smoothstep(.105,.33,abs(UV.x-foot)));
	VERTEX = vec3((UV.x-.5)*extent.x,(sole.y-UV.y)*extent.y,0.)+leg*planted_shift;
	NORMAL = vec3(0.,0.,1.);
	TANGENT = vec3(1.,0.,0.);
	BINORMAL = vec3(0.,1.,0.);
}
