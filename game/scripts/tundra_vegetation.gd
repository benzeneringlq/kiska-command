extends RefCounted
## Dense procedural tundra plants. One 64 m patch is built per rendered frame.
var grass: ArrayMesh
var fern: ArrayMesh
var bush: Mesh
var grass_material: ShaderMaterial
var bush_material: ShaderMaterial
var built_patches=0

func _init() -> void:
	grass=_plant_mesh(false)
	fern=_plant_mesh(true)
	var sphere=SphereMesh.new(); sphere.radial_segments=7; sphere.rings=3; sphere.radius=0.29; sphere.height=0.55
	var cluster=SurfaceTool.new(); cluster.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		var t=Transform3D(Basis.from_scale(Vector3(1.0,0.8+(i%3)*0.2,1.0)),Vector3(cos(i*2.4)*0.25,0.20+float(i%2)*0.12,sin(i*2.4)*0.25))
		cluster.append_from(sphere,0,t)
	bush=cluster.commit()
	grass_material=ShaderMaterial.new(); grass_material.shader=load("res://shaders/vegetation.gdshader")
	grass_material.set_shader_parameter("fade_distance",110.0)
	bush_material=ShaderMaterial.new(); bush_material.shader=grass_material.shader
	bush_material.set_shader_parameter("fade_distance",230.0)

func _plant_mesh(broad: bool) -> ArrayMesh:
	var st=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng=RandomNumberGenerator.new(); rng.seed=491 if broad else 913
	for i in range(9 if broad else 12):
		var angle=i*2.399
		var direction=Vector3(cos(angle),0,sin(angle))
		var side=Vector3(-direction.z,0,direction.x)
		var base=direction*rng.randf_range(0.04,0.65)
		var height=rng.randf_range(0.55,1.15) if not broad else rng.randf_range(0.45,0.95)
		var tip=base+direction*(0.65 if broad else 0.16)+Vector3.UP*height
		var width=0.11 if broad else 0.06
		var verts=[base-side*width,base+side*width,tip]
		for j in range(3):
			st.set_color(Color(0.30,0.38,0.15) if j==2 else Color(0.24,0.27,0.10))
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[j])
	return st.commit()

func build_patch(field: Node3D,tile: Node3D,offset: Vector2,seed_value: int) -> void:
	var node=Node3D.new(); node.name="TundraPatch"; tile.add_child(node)
	node.position=Vector3(offset.x,0,offset.y)
	var rng=RandomNumberGenerator.new(); rng.seed=seed_value
	for species in range(3):
		var transforms: Array[Transform3D]=[]
		var colors: Array[Color]=[]
		for i in range(2025 if species==0 else (64 if species==1 else 48)):
			var local=Vector3(rng.randf_range(0,64),0,rng.randf_range(0,64))
			if species==0:
				# Jittered grid keeps density even, avoiding accidental empty lawns.
				local=Vector3((i%45+rng.randf())*64.0/45,0,(i/45+rng.randf())*64.0/45)
			var p=tile.position+node.position+local
			var h=field.height_at(p.x,p.z)
			if h<2 or h>750: continue
			if absf(p.x-field.spawn_position.x)<55 and absf(p.z-field.spawn_position.z-120)<85: continue
			if p.z<=field.sites[0].position.z and p.z>=field.sites[-1].position.z and absf(p.x-field.road_x(p.z))<8: continue
			if absf(p.x-field.sites[5].position.x)<35 and absf(p.z-field.sites[5].position.z)<285: continue
			var blocked=false
			for rect in field.structures:
				if rect.grow(1.5).has_point(Vector2(p.x,p.z)): blocked=true; break
			if blocked: continue
			local.y=h-0.04
			var s=rng.randf_range(0.85,1.35)
			var scale=Vector3(s,s,s) if species!=1 else Vector3(s*1.3,s*0.65,s*1.2)
			transforms.append(Transform3D(Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(scale),local))
			colors.append(Color(rng.randf_range(0.85,1.20),rng.randf_range(0.87,1.13),0.85) if species!=1 else Color(0.25,0.34,0.15))
		var batch=MultiMesh.new(); batch.transform_format=MultiMesh.TRANSFORM_3D; batch.use_colors=true
		batch.mesh=grass if species==0 else (bush if species==1 else fern)
		batch.instance_count=transforms.size()
		for i in range(transforms.size()): batch.set_instance_transform(i,transforms[i]); batch.set_instance_color(i,colors[i])
		var draw=MultiMeshInstance3D.new(); draw.multimesh=batch
		draw.material_override=grass_material if species==0 else bush_material
		draw.visibility_range_end=120 if species==0 else 240
		draw.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		draw.extra_cull_margin=0.5
		node.add_child(draw)
	built_patches+=1
