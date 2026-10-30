extends RefCounted
## Vehicle-to-vehicle constraints, AI destinations, and walkable moving interiors.
var v: Node3D
var drive_target=Vector3.ZERO
var drive_order=false
var reverse_route=false
var route: Array[Vector3]=[]
var loading_aircraft: Node3D
var awaiting_ramp=false
var carrier: Node3D
var secured=false
var auto_lock=true
var cargo_pose=Transform3D.IDENTITY
var cargo: Array=[]
var walkers: Array=[]
var tow_target: Node3D
var tow_parent: Node3D
var doors_open=false
var dismount_requests: Array=[]
var parachute=false
var chute: Node3D
var tow_line: MeshInstance3D

func ground_vehicle() -> bool:
	return v.kind in ["JEEP","APC","TANK","TRUCK"]

func set_destination(p: Vector3) -> void:
	reverse_route=false
	drive_target=p; drive_order=true; route.clear()

func ai_input() -> Vector2:
	prepare_loading()
	if not drive_order: return Vector2.ZERO
	if not route.is_empty(): drive_target=route[0]
	var delta=drive_target-v.position; delta.y=0
	if delta.length()<2.8:
		if not route.is_empty():
			route.pop_front()
			if not route.is_empty(): drive_target=route[0]; return Vector2.ZERO
		if awaiting_ramp: return Vector2.ZERO
		drive_order=false
		if is_instance_valid(loading_aircraft):
			loading_aircraft.logistics.capture(v,true)
			loading_aircraft=null
		return Vector2.ZERO
	var yaw=atan2(delta.x,delta.z) if reverse_route else atan2(-delta.x,-delta.z)
	var error=wrapf(yaw-v.rotation.y,-PI,PI)
	var steer=clampf(error*1.8 if reverse_route else -error*1.8,-1,1)
	# Slow, forward steering; local obstacle probes supplement the route.
	var throttle=clampf(delta.length()/18,0.18,0.42)*(0.40 if absf(error)>0.65 else 1.0)
	var from=v.position+Vector3.UP*1.5
	var excludes=[v.get_rid()]
	if is_instance_valid(carrier): excludes.append(carrier.get_rid())
	for side in [-1,1]:
		var aim=from+v.global_basis.z*(5 if reverse_route else -5)+v.global_basis.x*side*1.2
		var hit=v.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,aim,1|8,excludes))
		if not hit.is_empty() and hit.normal.y<0.5:
			steer-=side*0.7; throttle*=0.45
	return Vector2(clampf(steer,-1,1),throttle if reverse_route else -throttle)

func request_loading(plane: Node3D) -> bool:
	if not ground_vehicle() or plane.kind!="CARGO" or not plane.supported_and_stopped() or not plane.logistics.has_room(v) or secured: return false
	loading_aircraft=plane; awaiting_ramp=true; drive_order=true; route.clear()
	var p=plane.to_local(v.position)
	if p.z<26:
		var side=maxf(absf(p.x),12.0)*(1 if p.x>=0 else -1)
		route.append(plane.to_global(Vector3(side,0,p.z)))
		route.append(plane.to_global(Vector3(side,0,33)))
	route.append(plane.to_global(Vector3(0,0,31)))
	return true

func prepare_loading() -> void:
	if not awaiting_ramp or not is_instance_valid(loading_aircraft): return
	var plane=loading_aircraft
	if not plane.supported_and_stopped(): drive_order=false; return
	if v.position.distance_to(plane.to_global(Vector3(0,0,26)))>8: return
	if not plane.logistics.doors_open and not plane.logistics.toggle_doors(): return
	awaiting_ramp=false
	load_into(plane)
	if not route.is_empty(): route[0]=plane.to_global(Vector3(0,0,31))

func load_into(plane: Node3D) -> bool:
	if not ground_vehicle() or plane.kind!="CARGO" or not plane.logistics.doors_open or absf(plane.speed)>1: return false
	if not is_instance_valid(v.occupants[0]): return false
	if not plane.logistics.has_room(v): return false
	loading_aircraft=plane; drive_order=true; route.clear()
	var slot=-5.0 if plane.logistics.cargo.size()==0 else 7.0
	var p=plane.to_local(v.position)
	if p.z<26:
		var side=maxf(absf(p.x),12.0)*(1 if p.x>=0 else -1)
		route.append(plane.to_global(Vector3(side,0,p.z)))
		route.append(plane.to_global(Vector3(side,0,33)))
	route.append_array([plane.to_global(Vector3(0,0,33)),plane.to_global(Vector3(0,0,22)),plane.to_global(Vector3(0,1.3,11)),plane.to_global(Vector3(0,1.3,slot))])
	return true

func request_unloading() -> bool:
	if not is_instance_valid(carrier) or not carrier.supported_and_stopped() or not is_instance_valid(v.occupants[0]): return false
	var plane=carrier
	if not plane.logistics.doors_open and not plane.logistics.toggle_doors(): return false
	plane.logistics.release(v)
	loading_aircraft=null; awaiting_ramp=false; reverse_route=true; drive_order=true
	route.assign([plane.to_global(Vector3(0,1.3,12)),plane.to_global(Vector3(0,0,22)),plane.to_global(Vector3(0,0,34)),plane.to_global(Vector3(0,0,46))])
	return true

func has_room(candidate: Node3D) -> bool:
	return candidate in cargo or cargo.size()<2

func inside(candidate: Node3D) -> bool:
	var p=v.to_local(candidate.position)
	var half_length=4.7 if candidate.kind=="TRUCK" else (3.6 if candidate.kind=="TANK" else 2.8)
	return absf(p.x)<2.6 and p.z> -14+half_length and p.z<16-half_length and p.y>0.4 and p.y<5

func capture(candidate: Node3D,force=false) -> bool:
	if v.kind!="CARGO" or not has_room(candidate) or not inside(candidate): return false
	if is_instance_valid(candidate.logistics.carrier) and candidate.logistics.carrier!=v: return false
	candidate.logistics.carrier=v
	if candidate not in cargo: cargo.append(candidate)
	if force or (candidate.logistics.auto_lock and not is_instance_valid(candidate.occupants[0])):
		candidate.logistics.secured=true
		candidate.logistics.auto_lock=true
		candidate.logistics.cargo_pose=v.global_transform.affine_inverse()*candidate.global_transform
		candidate.velocity=Vector3.ZERO; candidate.speed=0
		candidate.add_collision_exception_with(v); v.add_collision_exception_with(candidate)
	return true

func release(candidate: Node3D,airdrop=false) -> void:
	candidate.logistics.secured=false
	candidate.logistics.auto_lock=false
	candidate.remove_collision_exception_with(v); v.remove_collision_exception_with(candidate)
	if airdrop:
		candidate.global_transform=v.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,-1,36))
		candidate.velocity=v.velocity+v.global_basis.z*8
		candidate.speed=-v.velocity.dot(candidate.global_basis.z)
		candidate.logistics.carrier=null; cargo.erase(candidate)
		candidate.logistics.deploy_chute()
	else:
		candidate.position.y+=0.18

func toggle_secure() -> bool:
	if v.kind!="CARGO": return false
	for candidate in v.mission.vehicles:
		if candidate!=v and candidate.logistics.ground_vehicle() and inside(candidate): capture(candidate,false)
	var fixed=cargo.any(func(item): return item.logistics.secured)
	for candidate in cargo.duplicate():
		if fixed: release(candidate)
		else: capture(candidate,true)
	return not cargo.is_empty()

func toggle_doors() -> bool:
	if v.kind!="CARGO": return false
	# A partially loaded hull must not be crushed by the ramp closure.
	if doors_open:
		for item in v.mission.vehicles:
			if item==v: continue
			var p=v.to_local(item.position)
			if absf(p.x)<5 and p.z>12 and p.z<26 and p.y>0 and p.y<9: return false
		for actor in v.mission.actors+[v.mission.player]:
			var p=v.to_local(actor.position)
			if absf(p.x)<4.8 and p.z>16 and p.z<26.5 and p.y> -0.5 and p.y<9: return false
	doors_open=not doors_open
	v.ramp_visual.visible=doors_open; v.door_visual.visible=not doors_open
	v.ramp_collision.set_deferred("disabled",not doors_open)
	v.door_collision.set_deferred("disabled",doors_open)
	return true

func airdrop() -> bool:
	if v.kind!="CARGO" or not doors_open or cargo.is_empty(): return false
	for i in range(cargo.size()-1,-1,-1):
		var item=cargo[i]
		release(item,true)
		item.position+=v.global_basis.z*i*12
	return true

func deploy_chute() -> void:
	parachute=true
	if is_instance_valid(chute): chute.queue_free()
	chute=Node3D.new(); v.add_child(chute)
	var f=v.mission.field
	var material=f.mat("parachute",Color(0.55,0.48,0.30))
	var mesh=MeshInstance3D.new(); var canopy=SphereMesh.new(); canopy.radius=5; canopy.height=2; canopy.radial_segments=16; canopy.rings=4
	mesh.mesh=canopy; mesh.material_override=material; chute.add_child(mesh); mesh.position.y=10
	for side in [-1,1]:
		for end in [-1,1]:
			var rope=f.box(chute,Vector3(side*1.7,5.5,end*2),Vector3(0.035,9,0.035),f.mat("rope",Color(0.42,0.40,0.30)))
			rope.rotation.z=-side*0.12

func attach_tow(target: Node3D) -> bool:
	if not ground_vehicle() or not target.logistics.ground_vehicle() or target==v: return false
	if is_instance_valid(tow_target) or is_instance_valid(tow_parent) or is_instance_valid(target.logistics.tow_parent) or is_instance_valid(target.logistics.tow_target): return false
	if is_instance_valid(carrier) or is_instance_valid(target.logistics.carrier) or absf(v.speed)>1 or absf(target.speed)>1 or v.position.distance_to(target.position)>18: return false
	if is_instance_valid(target.occupants[0]): return false
	tow_target=target; target.logistics.tow_parent=v
	v.add_collision_exception_with(target); target.add_collision_exception_with(v)
	tow_line=v.mission.field.box(v,Vector3.ZERO,Vector3(0.045,0.045,1),v.mission.field.mat("tow_rope",Color(0.7,0.55,0.23)))
	return true

func detach_tow() -> void:
	if not is_instance_valid(tow_target): return
	v.remove_collision_exception_with(tow_target); tow_target.remove_collision_exception_with(v)
	tow_target.logistics.tow_parent=null; tow_target=null
	if is_instance_valid(tow_line): tow_line.queue_free()

func tow_tick(dt: float) -> bool:
	if not is_instance_valid(tow_parent): return false
	if tow_parent.health<=0: tow_parent.logistics.detach_tow(); return false
	var target=tow_parent.position+tow_parent.global_basis.z*8
	var delta=target-v.position; delta.y=0
	v.velocity.x=clampf(delta.x*3,-18,18); v.velocity.z=clampf(delta.z*3,-18,18)
	if delta.length()>0.2: v.rotation.y=lerp_angle(v.rotation.y,tow_parent.rotation.y,1-exp(-dt*3))
	v.speed=Vector2(v.velocity.x,v.velocity.z).length()
	return true

func free_floor_position(actor: Node3D,preferred: Vector3=Vector3.ZERO) -> Variant:
	var candidates: Array[Vector3]=[]
	if v.kind=="CARGO":
		var z=clampf(preferred.z if preferred!=Vector3.ZERO else -8.0,-15,14)
		for step in [0.0,1.5,-1.5,3.0,-3.0,5.0,-5.0,8.0,-8.0,12.0,-12.0]:
			for x in [3.45,-3.45]: candidates.append(Vector3(x,1.28,clampf(z+step,-16,15)))
	else:
		for z in [1.5,0.0,3.0]:
			for x in [0.0,-0.75,0.75]: candidates.append(Vector3(x,1.23,z))
	var capsule=CapsuleShape3D.new(); capsule.radius=0.36; capsule.height=1.8
	for local in candidates:
		var foot=v.to_global(local)
		var reserved=false
		# Physics queries can lag same-frame dismounts; reserve walker space too.
		for other in walkers:
			if is_instance_valid(other) and other!=actor and other.vehicle==v and other.position.distance_to(foot)<1.0: reserved=true; break
		if reserved: continue
		var query=PhysicsShapeQueryParameters3D.new(); query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,foot+Vector3.UP*0.9)
		query.collision_mask=15; query.exclude=[actor.get_rid()]
		if v.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return local
	return null

func walk_aboard(actor: Node3D,p: Vector3=Vector3.ZERO,from_vehicle: Node3D=null) -> bool:
	if v.kind not in ["TRUCK","CARGO"]: return false
	if is_instance_valid(actor.vehicle) and actor.vehicle!=v and actor.vehicle!=from_vehicle: return false
	var free=free_floor_position(actor,p)
	if free==null: return false
	# Commit only after a real capsule-sized free place has been found.
	var old=actor.vehicle
	if is_instance_valid(old):
		if actor.vehicle_seat>=0 and old.occupants[actor.vehicle_seat]==actor: old.occupants[actor.vehicle_seat]=null
		old.logistics.walkers.erase(actor)
	actor.vehicle=v; actor.vehicle_seat=-2
	actor.collision_layer=2 if actor==v.mission.player else 4; actor.collision_mask=15
	actor.velocity=Vector3.ZERO; actor.platform_floor_layers=0
	actor.global_position=v.to_global(free)
	if actor not in walkers: walkers.append(actor)
	if actor==v.mission.player:
		actor.vehicle_external=false
		actor.camera.position=Vector3(0,1.64,0)
		actor.equip_slot(actor.active_slot)
	else: actor.visual.visible=true
	return true

func retain_walker(actor: Node3D) -> void:
	if v.kind!="CARGO": return
	var p=v.to_local(actor.position)
	# Only an intentional walk down the open ramp may leave the interior.
	if doors_open and p.z>26.5:
		actor.vehicle=null; actor.vehicle_seat=-1; actor.platform_floor_layers=0xffffffff
		walkers.erase(actor); return
	var beyond=absf(p.x)>4.5 or p.z< -18 or p.y>7.0 or (p.z>17 and not doors_open) or p.y< -0.5
	if beyond:
		var free=free_floor_position(actor,p)
		if free!=null: actor.position=v.to_global(free); actor.velocity=Vector3.ZERO

func move_dependents(before: Transform3D) -> void:
	var delta=v.global_transform*before.affine_inverse()
	for actor in walkers.duplicate():
		if not is_instance_valid(actor) or actor.vehicle!=v or actor.vehicle_seat!=-2: walkers.erase(actor); continue
		actor.global_transform=delta*actor.global_transform
		var p=v.to_local(actor.position)
		if v.kind=="CARGO": retain_walker(actor)
		elif absf(p.x)>2 or absf(p.z)>6:
			actor.vehicle=null; actor.vehicle_seat=-1; actor.platform_floor_layers=0xffffffff; walkers.erase(actor)
	for item in cargo.duplicate():
		if not is_instance_valid(item): cargo.erase(item); continue
		if item.logistics.secured:
			item.global_transform=v.global_transform*item.logistics.cargo_pose
			for actor in item.occupants:
				if is_instance_valid(actor): actor.position=item.seat_position(actor.vehicle_seat)

func tick() -> void:
	if absf(v.speed)<2:
		for actor in dismount_requests.duplicate():
			if not is_instance_valid(actor) or actor.vehicle!=v: dismount_requests.erase(actor)
			elif v.exit_actor(actor): dismount_requests.erase(actor)
	if v.kind=="CARGO":
		for item in v.mission.vehicles:
			if item!=v and item.logistics.ground_vehicle() and inside(item): capture(item)
		for item in cargo.duplicate():
			if not item.logistics.secured and not inside(item): item.logistics.carrier=null; cargo.erase(item)
	if is_instance_valid(tow_target) and is_instance_valid(tow_line):
		var a=v.position+v.global_basis.z*2+Vector3.UP*0.6
		var b=tow_target.position-tow_target.global_basis.z*2+Vector3.UP*0.6
		tow_line.global_position=(a+b)/2; tow_line.scale.z=maxf(a.distance_to(b),0.1); tow_line.look_at(b)
