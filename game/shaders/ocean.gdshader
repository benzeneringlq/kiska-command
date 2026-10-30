shader_type spatial;
render_mode cull_disabled;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float waves = sin(world_position.x * 0.11 + TIME * 0.8) * sin(world_position.z * 0.09 - TIME * 0.6);
	ALBEDO = mix(vec3(0.075, 0.15, 0.18), vec3(0.13, 0.23, 0.26), waves * 0.5 + 0.5);
	ROUGHNESS = 0.34;
	NORMAL_MAP = vec3(0.5 + waves * 0.02, 0.5 + cos(world_position.z * 0.09 - TIME * 0.6) * 0.02, 1.0);
}
