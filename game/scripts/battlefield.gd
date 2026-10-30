extends Node3D
## Real Kiska relief: whole-island backdrop, 3x3 medium tiles and 3x3 collision tiles.
const LIMIT = 24576.0
const MIDDLE = 1024.0
var relief=preload("res://scripts/island_heightmap.gd").new()
var middle_chunks: Dictionary={}
var grading: Dictionary={}
var map_texture=preload("res://data/terrain/kiska_map.png")
const CHUNK = 256.0
const CELL = 4.0
var navigation = AStarGrid2D.new()
var nav_centre = Vector2i(99999,99999)
var nav_dirty = true
var obstacles: Array[Rect2] = []
var structures: Array[Rect2] = []
var houses: Array[Dictionary] = []
var materials: Dictionary = {}
var chunks: Dictionary = {}
var chunk_obstacles: Dictionary = {}
var mission: Node3D
var vegetation=preload("res://scripts/tundra_vegetation.gd").new()
var vegetation_jobs: Array=[]
var streamed_tiles=0
var peak_stream_ms=0.0
var spawn_position = Vector3(7200,0,5200)
var intel_position = Vector3(7300,0,4400)
var extraction = Vector3(4700,0,900)
var sites: Array[Dictionary] = [
	{"name":"Harbor staging area","position":Vector3(7200,0,5200)},
	{"name":"Harbor camp","position":Vector3(7300,0,4400)},
	{"name":"Road checkpoint","position":Vector3(6700,0,3700)},
	{"name":"Relay station","position":Vector3(6400,0,3100)},
	{"name":"Ridge outpost","position":Vector3(5700,0,2500)},
	{"name":"Forward airstrip","position":Vector3(5500,0,1800)},
	{"name":"Coastal extraction","position":Vector3(4700,0,900)}
]

func height_at(x: float,z: float) -> float:
	var h=relief.height_at(x,z)
	for pad in grading.get(Vector2i(floori(x/128),floori(z/128)),[]):
		var distance=Vector2(absf(x-pad.centre.x),absf(z-pad.centre.y))-pad.extent
		var edge=maxf(distance.x,distance.y)
		h=lerpf(h,pad.height,1.0-smoothstep(0.0,48.0,edge))
	return h

func _plan_grading() -> void:
	# Fictional engineering pads, local to camps; no island-wide height distortion.
	for i in range(sites.size()+1):
		var p: Vector3=sites[i].position if i<sites.size() else spawn_position+Vector3(0,0,120)
		var extent=Vector2(75,290) if i==5 else (Vector2(70,110) if i==sites.size() else Vector2(90,90))
		var pad={"centre":Vector2(p.x,p.z),"extent":extent,"height":relief.height_at(p.x,p.z)}
		for x in range(floori((p.x-extent.x-48)/128),ceili((p.x+extent.x+48)/128)+1):
			for z in range(floori((p.z-extent.y-48)/128),ceili((p.z+extent.y+48)/128)+1):
				var key=Vector2i(x,z)
				if not grading.has(key): grading[key]=[]
				grading[key].append(pad)

func ground(p: Vector3,offset: float=0.0) -> Vector3:
	return Vector3(p.x,height_at(p.x,p.z)+offset,p.z)

func road_x(z: float) -> float:
	if z>=sites[0].position.z: return sites[0].position.x
	if z<=sites[-1].position.z: return sites[-1].position.x
	for i in range(sites.size()-1):
		var a: Vector3=sites[i].position
		var b: Vector3=sites[i+1].position
		if z<=a.z and z>=b.z:
			return lerpf(a.x,b.x,smoothstep(0.0,1.0,(a.z-z)/(a.z-b.z)))
	return 0.0

func mat(key: String,color: Color,roughness: float=0.9) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m=StandardMaterial3D.new()
	m.albedo_color=color
	m.roughness=roughness
	materials[key]=m
	return m

func box(parent: Node3D,pos: Vector3,size: Vector3,material: Material,collide=false) -> MeshInstance3D:
	var mesh=MeshInstance3D.new()
	var b=BoxMesh.new()
	b.size=size
	mesh.mesh=b
	mesh.material_override=material
	parent.add_child(mesh)
	mesh.position=pos
	if collide:
		var body=StaticBody3D.new()
		parent.add_child(body)
		body.position=pos
		var shape=CollisionShape3D.new()
		var bounds=BoxShape3D.new()
		bounds.size=size
		shape.shape=bounds
		body.add_child(shape)
	return mesh

func _ready() -> void:
	_plan_grading()
	_plan_settlements()
	_build_far_terrain()
	_build_ocean()
	ensure_area(spawn_position)
	intel_position=ground(intel_position,0.8)
	extraction=ground(extraction)
	var beacon=mat("beacon",Color(0.3,0.75,0.65))
	for p in [spawn_position,extraction]:
		var ring=MeshInstance3D.new()
		var torus=TorusMesh.new()
		torus.inner_radius=7.8
		torus.outer_radius=8.0
		ring.mesh=torus
		ring.material_override=beacon
		add_child(ring)
		ring.position=ground(p,0.12)

func _process(_dt: float) -> void:
	if not is_instance_valid(mission.player): return
	# Discard jobs with their unloaded tile; build only the closest nearby patch.
	vegetation_jobs=vegetation_jobs.filter(func(job): return is_instance_valid(job.tile) and not job.tile.is_queued_for_deletion())
	var nearest=-1
	var distance=240.0*240.0
	var eye=Vector2(mission.player.position.x,mission.player.position.z)
	for i in range(vegetation_jobs.size()):
		var job=vegetation_jobs[i]
		var centre=Vector2(job.tile.position.x,job.tile.position.z)+job.offset+Vector2.ONE*32
		var d=centre.distance_squared_to(eye)
		if d<distance: nearest=i; distance=d
	if nearest>=0:
		var job=vegetation_jobs.pop_at(nearest)
		vegetation.build_patch(self,job.tile,job.offset,job.seed)

func _plan_settlements() -> void:
	var rng=RandomNumberGenerator.new()
	rng.seed=914
	for i in range(1,6):
		var centre: Vector3=sites[i].position
		for j in range(8 if i in [1,4] else 4):
			var p=centre+Vector3((-1 if j%2==0 else 1)*(22+(j/2)*13),0,(j%4-1.5)*22)
			var size=Vector2(rng.randf_range(5,8),rng.randf_range(6,10))
			var house={"position":p,"size":size,"roof":j%3}
			houses.append(house)
			var footprint=Rect2(Vector2(p.x-size.x/2,p.z-size.y/2),size)
			structures.append(footprint)
			obstacles.append(footprint.grow(0.7))

func _terrain_mesh(origin: Vector3,span: int,step: int) -> ArrayMesh:
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side=span/step+1
	for z in range(side):
		for x in range(side):
			var wx=origin.x+x*step
			var wz=origin.z+z*step
			var h=height_at(wx,wz)
			var normal=Vector3(height_at(wx-8,wz)-height_at(wx+8,wz),16,height_at(wx,wz-8)-height_at(wx,wz+8)).normalized()
			var rock=clampf((1-normal.y)*2.8+(h-450)/850,0,1)
			var c=Color(0.29,0.34,0.19).lerp(Color(0.38,0.39,0.36),rock)
			if h<5: c=c.lerp(Color(0.36,0.34,0.28),0.75)
			if h>1000: c=c.lerp(Color(0.67,0.69,0.66),clampf((h-1000)/250,0,0.6))
			if wz<=sites[0].position.z and wz>=sites[-1].position.z and absf(wx-road_x(wz))<7: c=Color(0.39,0.35,0.27)
			if absf(wx-sites[5].position.x)<16 and absf(wz-sites[5].position.z)<270: c=Color(0.25,0.27,0.26)
			if absf(wx-spawn_position.x)<55 and absf(wz-spawn_position.z-120)<85: c=Color(0.34,0.33,0.28)
			st.set_color(c)
			st.set_normal(normal)
			st.add_vertex(Vector3(x*step,h-origin.y,z*step))
	for z in range(side-1):
		for x in range(side-1):
			var a=z*side+x
			for idx in [a,a+1,a+side,a+1,a+side+1,a+side]: st.add_index(idx)
	for edge in range(4):
		for i in range(side-1):
			var p: Vector2
			var q: Vector2
			if edge==0: p=Vector2(i*step,0); q=p+Vector2(step,0)
			elif edge==1: p=Vector2(span,i*step); q=p+Vector2(0,step)
			elif edge==2: p=Vector2((i+1)*step,span); q=p-Vector2(step,0)
			else: p=Vector2(0,(i+1)*step); q=p-Vector2(0,step)
			var va=Vector3(p.x,height_at(origin.x+p.x,origin.z+p.y)-origin.y,p.y)
			var vb=Vector3(q.x,height_at(origin.x+q.x,origin.z+q.y)-origin.y,q.y)
			var base=side*side+(edge*(side-1)+i)*4
			st.set_normal(Vector3.UP)
			st.set_color(Color(0.29,0.33,0.22))
			for v in [va,vb,va-Vector3.UP*24,vb-Vector3.UP*24]: st.add_vertex(v)
			for index in [base,base+1,base+2,base+1,base+3,base+2]: st.add_index(index)
	return st.commit()

func _terrain_material(lod: int=0) -> ShaderMaterial:
	var key="terrain_%d" % lod
	if materials.has(key): return materials[key]
	var m=ShaderMaterial.new()
	m.shader=load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("lod",lod)
	materials[key]=m
	return m

func _update_lod_masks(p: Vector3) -> void:
	var origins=[chunk_key(p)-Vector2i.ONE,Vector2i(floori(p.x/MIDDLE),floori(p.z/MIDDLE))-Vector2i.ONE]
	var pools=[chunks,middle_chunks]
	for level in range(2):
		var mask=0
		for z in range(3):
			for x in range(3):
				if pools[level].has(origins[level]+Vector2i(x,z)): mask|=1<<(z*3+x)
		for lod in [1,2]:
			var m=_terrain_material(lod)
			m.set_shader_parameter("detail_origin" if level==0 else "middle_origin",origins[level])
			m.set_shader_parameter("detail_mask" if level==0 else "middle_mask",mask)

func _build_far_terrain() -> void:
	var mesh=MeshInstance3D.new()
	mesh.mesh=_terrain_mesh(Vector3(-LIMIT,0,-LIMIT),int(LIMIT*2),384)
	mesh.material_override=_terrain_material(2)
	add_child(mesh)
	mesh.position=Vector3(-LIMIT,0,-LIMIT)
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_ocean() -> void:
	var sea=MeshInstance3D.new()
	var plane=PlaneMesh.new()
	plane.size=Vector2.ONE*LIMIT*4
	sea.mesh=plane
	var water=ShaderMaterial.new()
	water.shader=load("res://shaders/ocean.gdshader")
	sea.material_override=water
	sea.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)

func chunk_key(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori(p.x/CHUNK),-96,95),clampi(floori(p.z/CHUNK),-96,95))

func desired_keys(p: Vector3,span: float=CHUNK) -> Array[Vector2i]:
	var limit=int(LIMIT/span)
	var centre=Vector2i(clampi(floori(p.x/span),-limit,limit-1),clampi(floori(p.z/span),-limit,limit-1))
	var keys: Array[Vector2i]=[]
	for x in range(-1,2):
		for z in range(-1,2):
			var key=centre+Vector2i(x,z)
			if key.x>=-limit and key.x<limit and key.y>=-limit and key.y<limit: keys.append(key)
	keys.sort_custom(func(a,b): return a.distance_squared_to(centre)<b.distance_squared_to(centre))
	return keys

func _build_middle(key: Vector2i) -> void:
	var mesh=MeshInstance3D.new()
	var origin=Vector3(key.x*MIDDLE,0,key.y*MIDDLE)
	mesh.mesh=_terrain_mesh(origin,1024,32)
	mesh.material_override=_terrain_material(1)
	mesh.position=origin
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	middle_chunks[key]=mesh

func _trim_middle(p: Vector3) -> void:
	var wanted=desired_keys(p,MIDDLE)
	for key in middle_chunks.keys():
		if key not in wanted:
			middle_chunks[key].queue_free()
			middle_chunks.erase(key)

func ensure_area(p: Vector3) -> void:
	for key in desired_keys(p,MIDDLE):
		if not middle_chunks.has(key): _build_middle(key)
	_trim_middle(p)
	for key in desired_keys(p):
		if not chunks.has(key): _build_chunk(key)
	_trim_chunks(p)
	_update_lod_masks(p)

func stream_tick(p: Vector3) -> void:
	# At most one new terrain tile per frame, prioritizing nearby collision.
	var built=false
	for key in desired_keys(p):
		if not chunks.has(key):
			var begin=Time.get_ticks_usec()
			_build_chunk(key)
			peak_stream_ms=maxf(peak_stream_ms,float(Time.get_ticks_usec()-begin)/1000)
			streamed_tiles+=1
			built=true
			break
	if not built:
		for key in desired_keys(p,MIDDLE):
			if not middle_chunks.has(key):
				_build_middle(key)
				break
	_trim_middle(p)
	_trim_chunks(p)
	_update_lod_masks(p)

func _trim_chunks(p: Vector3) -> void:
	var wanted=desired_keys(p)
	for key in chunks.keys():
		if key not in wanted:
			chunks[key].queue_free()
			chunks.erase(key)
			chunk_obstacles.erase(key)
			nav_dirty=true

func _build_chunk(key: Vector2i) -> void:
	var tile=Node3D.new()
	tile.name="Tile_%d_%d" % [key.x,key.y]
	add_child(tile)
	tile.position=Vector3(key.x*CHUNK,0,key.y*CHUNK)
	var terrain=MeshInstance3D.new()
	terrain.mesh=_terrain_mesh(tile.position,256,8)
	terrain.material_override=_terrain_material()
	tile.add_child(terrain)
	terrain.create_trimesh_collision()
	var rect=Rect2(Vector2(tile.position.x,tile.position.z),Vector2(CHUNK,CHUNK))
	for house in houses:
		if rect.has_point(Vector2(house.position.x,house.position.z)): _build_house(tile,house)
	var tile_obstacles: Array[Rect2]=[]
	_build_rocks(tile,key,tile_obstacles)
	for x in range(4):
		for z in range(4):
			vegetation_jobs.append({"tile":tile,"offset":Vector2(x*64,z*64),"seed":absi(key.x*18497+key.y*7283+x*113+z*17)})
	# Low walls and crates around objectives, with a clear road and wide entrances.
	for i in [1,2,3,4,5]:
		var p: Vector3=sites[i].position+Vector3(0,0,12)
		if rect.has_point(Vector2(p.x,p.z)):
			for side in [-1,1]:
				var wp=p+Vector3(side*10,0,0)
				box(tile,ground(wp)+Vector3(0,0.6,0)-tile.position,Vector3(5,1.2,1.2),mat("sand",Color(0.48,0.43,0.30)),true)
				tile_obstacles.append(Rect2(Vector2(wp.x-3,wp.z-1.2),Vector2(6,2.4)))
	chunks[key]=tile
	chunk_obstacles[key]=tile_obstacles
	_batch_static_geometry(tile)
	nav_dirty=true

func _build_house(tile: Node3D,house: Dictionary) -> void:
	var p: Vector3=house.position
	var s: Vector2=house.size
	var base=ground(p)-tile.position
	var wall=mat("plaster",Color(0.58,0.55,0.44))
	var roof=mat("roof%d" % house.roof,[Color(0.32,0.27,0.22),Color(0.28,0.32,0.29),Color(0.4,0.32,0.25)][house.roof])
	var floor_mat=mat("floor",Color(0.36,0.34,0.28))
	box(tile,base+Vector3(0,0.1,0),Vector3(s.x,0.22,s.y),floor_mat,true)
	# Front doorway is 1.6m wide with a real opening; side windows have no glass.
	for side in [-1,1]:
		var width=(s.x-1.6)/2
		box(tile,base+Vector3(side*(0.8+width/2),1.65,s.y/2),Vector3(width,3.1,0.24),wall,true)
	box(tile,base+Vector3(0,2.8,s.y/2),Vector3(1.6,0.8,0.24),wall,true)
	box(tile,base+Vector3(0,1.65,-s.y/2),Vector3(s.x,3.1,0.24),wall,true)
	for side in [-1,1]:
		var half=(s.y-1.8)/2
		for end in [-1,1]:
			box(tile,base+Vector3(side*s.x/2,1.65,end*(0.9+half/2)),Vector3(0.24,3.1,half),wall,true)
		box(tile,base+Vector3(side*s.x/2,0.65,0),Vector3(0.24,1.1,1.8),wall,true)
		box(tile,base+Vector3(side*s.x/2,2.9,0),Vector3(0.24,0.6,1.8),wall,true)
	box(tile,base+Vector3(0,3.25,0),Vector3(s.x+0.5,0.22,s.y+0.5),roof,true)
	# A sloped doorstep reaches the actual terrain height, including hillside homes.
	var ramp=SurfaceTool.new()
	ramp.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outside=ground(p+Vector3(0,0,s.y/2+1.8))-tile.position+Vector3.UP*0.025
	var corners=[base+Vector3(-0.79,0.22,s.y/2+0.01),base+Vector3(0.79,0.22,s.y/2+0.01),outside+Vector3(-0.79,0,0),outside+Vector3(0.79,0,0)]
	for idx in [0,1,2,1,3,2]: ramp.add_vertex(corners[idx])
	ramp.generate_normals()
	var approach=MeshInstance3D.new()
	approach.mesh=ramp.commit()
	approach.material_override=floor_mat
	tile.add_child(approach)
	approach.create_trimesh_collision()
	box(tile,base+Vector3(-s.x*0.25,0.58,-s.y*0.25),Vector3(1.5,0.85,0.8),mat("wood",Color(0.3,0.24,0.17)),true)

func _build_rocks(tile: Node3D,key: Vector2i,_blocked: Array[Rect2]) -> void:
	# Kiska has maritime tundra, not conifer woodland. Low-cost scattered rocks.
	var rng=RandomNumberGenerator.new()
	rng.seed=abs(key.x*928371+key.y*192811+41)
	var transforms: Array[Transform3D]=[]
	for i in range(72):
		var p=tile.position+Vector3(rng.randf_range(4,252),0,rng.randf_range(4,252))
		if height_at(p.x,p.z)<3 or absf(p.x-road_x(p.z))<18: continue
		var near_site=false
		for site in sites:
			if Vector2(p.x,p.z).distance_to(Vector2(site.position.x,site.position.z))<100: near_site=true; break
		if near_site: continue
		var scale=Vector3(rng.randf_range(0.5,2),rng.randf_range(0.25,0.9),rng.randf_range(0.5,1.5))
		transforms.append(Transform3D(Basis.from_scale(scale),ground(p)-tile.position))
	var rock=SphereMesh.new()
	rock.radial_segments=6
	rock.rings=3
	var batch=MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.mesh=rock
	batch.instance_count=transforms.size()
	for j in range(transforms.size()): batch.set_instance_transform(j,transforms[j])
	var instance=MultiMeshInstance3D.new()
	instance.multimesh=batch
	instance.material_override=mat("tundra_rock",Color(0.34,0.35,0.31))
	tile.add_child(instance)

func _batch_static_geometry(parent: Node3D) -> void:
	var batches: Dictionary={}
	for child in parent.get_children():
		if not child is MeshInstance3D: continue
		if not child.mesh is BoxMesh: continue
		var key=child.material_override.get_instance_id()
		if not batches.has(key): batches[key]=[]
		batches[key].append(child)
	for key in batches:
		var surface=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for instance in batches[key]: surface.append_from(instance.mesh,0,instance.transform)
		var merged=MeshInstance3D.new()
		merged.mesh=surface.commit()
		merged.material_override=batches[key][0].material_override
		parent.add_child(merged)
		for instance in batches[key]: instance.queue_free()

func _refresh_navigation(from: Vector3) -> void:
	var centre=Vector2i(roundi(from.x/128),roundi(from.z/128))
	if centre==nav_centre and not nav_dirty: return
	nav_centre=centre
	nav_dirty=false
	navigation.region=Rect2i(centre*32-Vector2i(64,64),Vector2i(128,128))
	navigation.cell_size=Vector2(CELL,CELL)
	navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for x in range(navigation.region.position.x,navigation.region.end.x):
		for z in range(navigation.region.position.y,navigation.region.end.y):
			var h=height_at(x*CELL,z*CELL)
			if h<1 or absf(height_at(x*CELL+CELL,z*CELL)-h)>3 or absf(height_at(x*CELL,z*CELL+CELL)-h)>3: navigation.set_point_solid(Vector2i(x,z))
	var blocked=obstacles.duplicate()
	for list in chunk_obstacles.values(): blocked.append_array(list)
	for rect in blocked:
		var lo=Vector2i(floori(rect.position.x/CELL),floori(rect.position.y/CELL))
		var hi=Vector2i(ceili(rect.end.x/CELL),ceili(rect.end.y/CELL))
		for x in range(lo.x,hi.x+1):
			for z in range(lo.y,hi.y+1):
				var c=Vector2i(x,z)
				if navigation.is_in_boundsv(c): navigation.set_point_solid(c)

func safe_cell(p: Vector3) -> Vector2i:
	var r=navigation.region
	var c=Vector2i(clampi(roundi(p.x/CELL),r.position.x,r.end.x-1),clampi(roundi(p.z/CELL),r.position.y,r.end.y-1))
	if not navigation.is_point_solid(c): return c
	for radius in range(1,10):
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				var alt=c+Vector2i(x,z)
				if navigation.is_in_boundsv(alt) and not navigation.is_point_solid(alt): return alt
	return c

func route(from: Vector3,to: Vector3) -> PackedVector3Array:
	_refresh_navigation(from)
	var result=PackedVector3Array()
	var path=navigation.get_id_path(safe_cell(from),safe_cell(to))
	for p in path: result.append(ground(Vector3(p.x*CELL,0,p.y*CELL),0.05))
	return result
