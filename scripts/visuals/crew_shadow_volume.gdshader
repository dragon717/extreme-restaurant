shader_type spatial;
uniform bool limbed = true;
void vertex() {
	// Keep the body grounded, with separated leg silhouettes at contact.
	if(limbed && VERTEX.y<.34) {
		VERTEX.z += sign(VERTEX.x)*sin(INSTANCE_CUSTOM.r*6.2831853)*(.34-VERTEX.y)*.44*INSTANCE_CUSTOM.g;
	}
}
