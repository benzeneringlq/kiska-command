shader_type spatial;
uniform int lod = 0;
uniform ivec2 detail_origin;
uniform int detail_mask = 0;
uniform ivec2 middle_origin;
uniform int middle_mask = 0;
varying vec3 world_position;
bool tile_loaded(vec2 p, float size, ivec2 origin, int mask) {
	ivec2 c = ivec2(floor(p / size)) - origin;
	if (c.x < 0 || c.y < 0 || c.x > 2 || c.y > 2) { return false; }
	return (mask & (1 << (c.y * 3 + c.x))) != 0;
}
float ground_noise(vec2 p) {
	vec2 cell=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	float a=fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
	float b=fract(sin(dot(cell+vec2(1,0),vec2(127.1,311.7)))*43758.5453);
	float c=fract(sin(dot(cell+vec2(0,1),vec2(127.1,311.7)))*43758.5453);
	float d=fract(sin(dot(cell+vec2(1,1),vec2(127.1,311.7)))*43758.5453);
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// Remove covered surfaces instead of stacking different approximations.
	if (lod > 0 && tile_loaded(world_position.xz, 256.0, detail_origin, detail_mask)) { discard; }
	if (lod > 1 && tile_loaded(world_position.xz, 1024.0, middle_origin, middle_mask)) { discard; }
	float grain = sin(world_position.x * 0.73 + sin(world_position.z * 0.21)) * sin(world_position.z * 0.61);
	float patches = ground_noise(world_position.xz * 0.13);
	float moss = ground_noise(world_position.xz * 1.3);
	ALBEDO = COLOR.rgb * (0.80 + grain * 0.035 + patches * 0.25 + moss * 0.16);
	ROUGHNESS = 0.96;
}
