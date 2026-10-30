shader_type spatial;
render_mode cull_disabled;
uniform float fade_distance=110.0;
void vertex() {
	vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float distance_to_eye=distance(world,CAMERA_POSITION_WORLD);
	float fade=1.0-smoothstep(fade_distance-25.0,fade_distance,distance_to_eye);
	VERTEX.y*=fade;
	VERTEX.x+=sin(TIME*1.7+world.x*0.21+world.z*0.17)*0.06*max(VERTEX.y,0.0);
}
void fragment() {
	ALBEDO=COLOR.rgb;
	ROUGHNESS=0.95;
	BACKLIGHT=COLOR.rgb*0.15;
}
