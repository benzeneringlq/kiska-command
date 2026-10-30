extends CharacterBody3D
## Collision-based vehicle motion with gravity and ray-probed spring suspension.
var mission: Node3D
var kind="JEEP"
var display_name="Utility 4x4"
var health=500.0
var max_health=500.0
var speed=0.0
var occupants: Array=[]
var reservations: Dictionary={}
var seat_count=4
var rotor: Node3D
var visuals: Node3D
var cab_frame: Node3D
var throttle=0.0
var previous_yaw=0.0
var wheels: Array=[]
var suspension_contacts=0
var tilt_velocity=Vector2.ZERO
var wheel_spin=0.0
var logistics=preload("res://scripts/vehicle_logistics.gd").new()
var ramp_visual: Node3D
var door_visual: Node3D
var ramp_collision: CollisionShape3D
var door_collision: CollisionShape3D

func _ready() -> void:
	logistics.v=self
	collision_layer=8
	collision_mask=1|8
	if kind=="APC": health=1100; display_name="Armoured transport"
	if kind=="HELI": health=700; seat_count=6; display_name="Utility helicopter"
	if kind=="HMG": health=350; seat_count=1; display_name="M2 fixed machine gun"
	if kind=="TRUCK": health=950; seat_count=4; display_name="Heavy transport truck"
	if kind=="TANK": health=2200; seat_count=3; display_name="Main battle tank"
	if kind=="CARGO": health=5000; seat_count=4; display_name="Atlas heavy transport"
	max_health=health
	occupants.resize(seat_count)
	if kind=="CARGO":
		_collision_box(Vector3(0,1.05,-1),Vector3(9.8,0.3,36))
		for side in [-1,1]:
			_collision_box(Vector3(side*4.85,5.15,-2),Vector3(0.3,8.3,38))
		_collision_box(Vector3(0,9.25,-2),Vector3(10,0.3,38))
		_collision_box(Vector3(0,3.5,-19),Vector3(9.6,4.6,0.3))
		for x in [-3.6,3.6]: _collision_box(Vector3(x,0.65,8),Vector3(1.5,1.3,3))
		_collision_box(Vector3(0,0.65,-22),Vector3(1.5,1.3,2))
		door_collision=_collision_box(Vector3(0,5.2,17),Vector3(9.5,8,0.25))
		ramp_collision=_collision_box(Vector3(0,0.6,21.5),Vector3(9.5,0.18,9.2))
		ramp_collision.rotation.x=0.13; ramp_collision.disabled=true
	elif kind=="TRUCK":
		_collision_box(Vector3(0,0.65,0),Vector3(2.8,1.0,8.8))
		_collision_box(Vector3(0,1.7,-3),Vector3(2.7,1.7,2.2))
		for x in [-1.4,1.4]: _collision_box(Vector3(x,1.7,1),Vector3(0.12,1.4,5.5))
	else:
		var bounds=Vector3(2.1,1.35,4.0) if kind=="JEEP" else Vector3(2.8,1.9,5.3)
		if kind=="HELI": bounds=Vector3(2.4,2.2,5.7)
		if kind=="HMG": bounds=Vector3(0.7,1.4,0.7)
		if kind=="TANK": bounds=Vector3(3.5,2.1,7)
		_collision_box(Vector3(0,bounds.y/2+0.25,0),bounds)
	visuals=Node3D.new()
	add_child(visuals)
	_build_model()

func _collision_box(p: Vector3,size: Vector3) -> CollisionShape3D:
	var shape=CollisionShape3D.new(); var box=BoxShape3D.new(); box.size=size
	shape.shape=box; shape.position=p; add_child(shape)
	return shape

func seat_label(seat: int) -> String:
	if seat==0: return "Driver / pilot"
	if seat==1 and kind in ["APC","TANK"]: return "Gunner"
	return "Passenger %d" % seat

func can_shoot(seat: int) -> bool:
	return seat!=0 or kind=="HMG"

func access_distance(p: Vector3) -> float:
	if kind=="CARGO":
		var local=to_local(p)
		if absf(local.x)<4.5 and local.z> -18 and local.z<25 and local.y> -0.8 and local.y<9.5: return 0
		return minf(p.distance_to(to_global(Vector3(-5,0,-22))),p.distance_to(to_global(Vector3(0,0,26))))
	if kind=="TRUCK": return minf(p.distance_to(position),p.distance_to(to_global(Vector3(0,0,5))))
	return p.distance_to(position)

func set_destination(p: Vector3) -> void:
	logistics.set_destination(p)

func _build_model() -> void:
	preload("res://scripts/vehicle_model.gd").new().build(self)

func _suspension(dt: float) -> void:
	suspension_contacts=0
	var normal=Vector3.ZERO
	var lift=0.0
	var count=maxi(wheels.size(),1)
	for wheel in wheels:
		var mount=global_transform*Vector3(wheel.x,0.65,wheel.z)
		var query=PhysicsRayQueryParameters3D.create(mount,mount-Vector3.UP*1.55,1|8,[get_rid()])
		var hit=get_world_3d().direct_space_state.intersect_ray(query)
		var extension=-0.20
		if not hit.is_empty() and hit.normal.y>0.25:
			var distance=mount.y-hit.position.y
			var point_velocity=velocity.y-tilt_velocity.x*wheel.z+tilt_velocity.y*wheel.x
			lift+=clampf((0.90-distance)*120-point_velocity*12,0,100)/count
			normal+=hit.normal
			suspension_contacts+=1
			extension=clampf(to_local(hit.position).y,-0.28,0.28)
		wheel.pivot.position.y=lerpf(wheel.pivot.position.y,wheel.radius+extension,1-exp(-dt*20))
	velocity.y+=(lift-18.0)*dt
	if suspension_contacts>=2:
		var local_normal=Basis(Vector3.UP,rotation.y).inverse()*normal.normalized()
		var desired=Vector2(atan2(local_normal.z,local_normal.y),-atan2(local_normal.x,local_normal.y))
		desired=desired.clamp(Vector2.ONE*-0.72,Vector2.ONE*0.72)
		tilt_velocity+=(desired-Vector2(rotation.x,rotation.z))*dt*45-tilt_velocity*dt*11
	else: tilt_velocity*=exp(-dt*0.6)
	rotation.x=clampf(rotation.x+tilt_velocity.x*dt,-0.9,0.9)
	rotation.z=clampf(rotation.z+tilt_velocity.y*dt,-0.9,0.9)

func _park_far() -> void:
	# Distant parked vehicles have no active collision tiles. Approximate their
	# attitude from the offline heightmap until actual ray contacts are available.
	var x=position.x; var z=position.z
	var n=Vector3(mission.field.height_at(x-2,z)-mission.field.height_at(x+2,z),4,mission.field.height_at(x,z-2)-mission.field.height_at(x,z+2)).normalized()
	var local_normal=Basis(Vector3.UP,rotation.y).inverse()*n
	rotation.x=clampf(atan2(local_normal.z,local_normal.y),-0.65,0.65)
	rotation.z=clampf(-atan2(local_normal.x,local_normal.y),-0.65,0.65)
	position.y=mission.field.height_at(x,z)+0.12
	velocity=Vector3.ZERO

func mounted_weapon_id(seat: int=0) -> int:
	if kind=="HMG" or (kind in ["APC","TANK"] and seat==1): return 35
	return -1

func free_seat(prefer_driver=false) -> int:
	var start=0 if prefer_driver else 1
	if kind=="HMG": start=0
	for i in range(start,seat_count):
		if not is_instance_valid(occupants[i]) and not reservations.has(i): return i
	return -1

func reserve(actor: Node3D) -> int:
	for i in reservations:
		if reservations[i]==actor: return i
	var seat=free_seat(true)
	if seat>=0: reservations[seat]=actor
	return seat

func board(actor: Node3D,seat: int=-1) -> bool:
	if health<=0: return false
	if seat>=0 and (seat>=seat_count or is_instance_valid(occupants[seat]) and occupants[seat]!=actor): return false
	if seat>=0 and reservations.has(seat) and reservations[seat]!=actor: return false
	if actor.vehicle==self:
		if actor.vehicle_seat>=0: occupants[actor.vehicle_seat]=null
		else: logistics.walkers.erase(actor)
		actor.vehicle=null
	elif is_instance_valid(actor.vehicle): return false
	if seat<0: seat=free_seat(actor==mission.player)
	if seat<0 or seat>=seat_count or is_instance_valid(occupants[seat]): return false
	if reservations.has(seat) and reservations[seat]!=actor: return false
	reservations.erase(seat)
	occupants[seat]=actor
	actor.vehicle=self
	actor.vehicle_seat=seat
	actor.collision_layer=0
	actor.collision_mask=0
	if actor==mission.player:
		actor.rotation.y=rotation.y
		actor.pitch=0
		if mounted_weapon_id(seat)>=0: actor.equip_profile(mounted_weapon_id(seat))
		else: actor.equip_slot(actor.active_slot)
		if kind=="HMG": visuals.visible=false
	else:
		actor.boarding_target=null
		actor.visual.visible=false
		actor.status="ABOARD"
	actor.global_position=seat_position(seat)
	return true

func seat_position(seat: int) -> Vector3:
	var p=Vector3(-0.46,0.34,-0.16)
	if kind=="APC": p=Vector3(0,2.0,-0.5)
	if kind=="HELI": p=Vector3(-0.45,0.35,-2.16)
	if kind=="HMG": p=Vector3(0,0.05,1.0)
	if kind=="TRUCK": p=Vector3(-0.65,0.95,-3)
	if kind=="TANK": p=Vector3(-0.7,1.5,-1.8)
	if kind=="CARGO": p=Vector3(-1.1,3.6,-24)
	if seat==1 and kind in ["TANK","APC"]: p=Vector3(0,2.1,-0.5)
	if kind=="TRUCK" and seat>0: p=Vector3(0.65,0.95,-3) if seat==1 else Vector3(-0.7 if seat==2 else 0.7,1.25,1)
	elif seat>0: p+=Vector3(-0.5 if seat%2==0 else 0.5,0,1.0+floori(float(seat-1)/2)*0.6)
	return global_transform*p

func containing_transport() -> Node3D:
	# Resolve spatial containment at the time of exiting, not only a cached lock.
	for other in mission.vehicles:
		if other==self or other.kind!="CARGO": continue
		var p=other.to_local(position)
		if absf(p.x)<4.6 and p.z> -18 and p.z<20 and p.y>0.35 and p.y<6:
			return other
	return null

func supported_and_stopped() -> bool:
	if absf(speed)>2 or Vector2(velocity.x,velocity.z).length()>2 or absf(velocity.y)>1.5: return false
	if is_on_floor(): return true
	var probes=[Vector3.ZERO,Vector3(-3.6,0,8),Vector3(3.6,0,8),Vector3(0,0,-22)] if kind=="CARGO" else [Vector3.ZERO]
	for probe in probes:
		var p=to_global(probe)
		var hit=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*0.4,p-Vector3.UP*0.8,1,[get_rid()]))
		if not hit.is_empty() and hit.normal.y>0.65: return true
	return false

func safe_exterior_position(actor: Node3D) -> Variant:
	var candidates: Array[Vector3]=[]
	if kind=="CARGO":
		for z in [28,30,32]:
			for x in [0,2,-2,4,-4]: candidates.append(Vector3(x,0,z))
	else:
		for z in [1.5,-1.5,3.5,-3.5]:
			for x in [3.2,-3.2]: candidates.append(Vector3(x,0,z))
		candidates.append(Vector3(0,0,5)); candidates.append(Vector3(0,0,-5))
	var capsule=CapsuleShape3D.new(); capsule.radius=0.36; capsule.height=1.8
	for local in candidates:
		var p=to_global(local)
		var hit=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*3,p-Vector3.UP*4,1,[get_rid()]))
		if hit.is_empty() or hit.normal.y<0.65: continue
		var foot=hit.position+Vector3.UP*0.08
		var occupied=false
		for other in mission.actors+[mission.player]:
			if other!=actor and not is_instance_valid(other.vehicle) and other.position.distance_to(foot)<1.0: occupied=true; break
		if occupied: continue
		var query=PhysicsShapeQueryParameters3D.new(); query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,foot+Vector3.UP*0.9)
		query.collision_mask=15; query.exclude=[actor.get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return foot
	return null

func exit_actor(actor: Node3D,forced=false) -> bool:
	var container=containing_transport()
	if is_instance_valid(container):
		if not container.logistics.walk_aboard(actor,container.to_local(position),self):
			mission.radio("No safe space on the cargo floor."); return false
		return true
	if kind=="CARGO" and not forced:
		if actor.vehicle_seat>=0 and (not supported_and_stopped() or not logistics.doors_open):
			var entered=logistics.walk_aboard(actor)
			if entered: mission.radio("Inside cargo bay. Land, stop and open the ramp to exit.")
			return entered
		if not supported_and_stopped(): mission.radio("Land and stop before leaving the aircraft."); return false
		if not logistics.doors_open: mission.radio("Open this aircraft ramp before leaving."); return false
	elif not forced and (absf(speed)>4 or (kind=="HELI" and not supported_and_stopped())):
		mission.radio("Stop or land before dismounting."); return false
	var p=safe_exterior_position(actor)
	if p==null and forced:
		var rough=to_global(Vector3(0,0,28) if kind=="CARGO" else Vector3(3.2,0,1.5))
		mission.field.ensure_area(rough); p=mission.field.ground(rough,0.35)
	if p==null: mission.radio("Exit blocked. Clear space beside the vehicle."); return false
	var seat=actor.vehicle_seat
	if seat>=0 and occupants[seat]==actor: occupants[seat]=null
	logistics.walkers.erase(actor)
	actor.vehicle=null; actor.vehicle_seat=-1; actor.velocity=Vector3.ZERO
	actor.platform_floor_layers=0xffffffff
	actor.collision_layer=2 if actor==mission.player else 4; actor.collision_mask=15
	actor.global_position=p
	if actor==mission.player:
		actor.vehicle_external=false; actor.camera.position=Vector3(0,1.64,0)
		visuals.visible=true; actor.equip_slot(actor.active_slot)
	else: actor.visual.visible=true; actor.command="FOLLOW"
	return true

func _physics_process(dt: float) -> void:
	if not mission.active(): return
	if health<=0 and kind not in ["HELI","CARGO"] and not is_instance_valid(logistics.tow_parent): return
	if logistics.secured and is_instance_valid(logistics.carrier):
		global_transform=logistics.carrier.global_transform*logistics.cargo_pose
		velocity=Vector3.ZERO
		return
	var before_transform=global_transform
	var ai_driven=is_instance_valid(occupants[0]) and occupants[0]!=mission.player and occupants[0].health>0
	if logistics.parachute and position.distance_to(mission.player.position)>250:
		velocity.y=maxf(velocity.y-18*dt,-7)
		position+=velocity*dt
		var ground_y=mission.field.height_at(position.x,position.z)+0.12
		if position.y<=ground_y:
			position.y=ground_y; velocity=Vector3.ZERO; speed=0
			logistics.parachute=false
			if is_instance_valid(logistics.chute): logistics.chute.queue_free()
		return
	var driver=occupants[0]
	var driven=is_instance_valid(driver) and driver==mission.player
	cab_frame.visible=true
	var distance=position.distance_to(mission.player.position)
	visuals.visible=distance<850 and not (kind=="HMG" and driven)
	if distance>250 and is_instance_valid(logistics.tow_parent):
		var parent=logistics.tow_parent
		if parent.health<=0: parent.logistics.detach_tow(); return
		var goal=parent.position+parent.global_basis.z*8
		position=position.move_toward(goal,18*dt)
		rotation.y=lerp_angle(rotation.y,parent.rotation.y,1-exp(-dt*3))
		_park_far()
		return
	if distance>250 and ai_driven and logistics.ground_vehicle() and not is_instance_valid(logistics.carrier) and not is_instance_valid(logistics.tow_parent) and logistics.walkers.is_empty():
		# The player streams local collision only. Distant AI uses offline relief
		# instead of falling through terrain tiles that are intentionally unloaded.
		var control=logistics.ai_input()
		speed=move_toward(speed,-control.y*16,dt*8)
		rotation.y-=control.x*dt*1.1*clampf(absf(speed)/4,0,1)
		var step=-Basis(Vector3.UP,rotation.y).z*speed*dt
		var next=position+step
		var height=mission.field.height_at(next.x,next.z)
		if height>1 and absf(height-mission.field.height_at(position.x,position.z))<maxf(step.length()*0.7,0.15):
			position=next
		else: speed=0; logistics.drive_order=false
		_park_far()
		logistics.move_dependents(before_transform); logistics.tick()
		return
	if distance>250 and not driven and not ai_driven and logistics.walkers.is_empty() and logistics.cargo.is_empty() and not is_instance_valid(logistics.carrier):
		if kind in ["HELI","CARGO"] and position.y>mission.field.height_at(position.x,position.z)+0.2:
			# Airborne helicopters keep falling even outside loaded collision tiles.
			velocity.y-=18.0*dt
			position+=velocity*dt
			var ground_y=mission.field.height_at(position.x,position.z)+0.12
			if position.y<=ground_y:
				if velocity.y< -10: take_damage((-velocity.y-10)*8)
				position.y=ground_y; velocity=Vector3.ZERO
		else: _park_far()
		return
	var input=Input.get_vector("left","right","forward","back") if driven and not mission.benchmark_mode else Vector2.ZERO
	if ai_driven: input=logistics.ai_input()
	previous_yaw=rotation.y
	if kind=="HMG": return
	if kind=="CARGO":
		_plane_motion(dt,input,driven,ai_driven)
	elif kind=="HELI":
		if (driven or ai_driven) and health>0:
			rotation.y-=input.x*dt*1.0
			var horizontal=-global_basis.z*(-input.y)*32
			velocity.x=move_toward(velocity.x,horizontal.x,dt*7)
			velocity.z=move_toward(velocity.z,horizontal.z,dt*7)
			var vertical=0.0
			if driven: vertical=(1.0 if Input.is_action_pressed("jump") else 0.0)-(1.0 if Input.is_action_pressed("crouch") else 0.0)
			elif logistics.drive_order: vertical=clampf((mission.field.height_at(position.x,position.z)+25-position.y)/20,-1,1)
			else: vertical=-0.4
			# Gravity is present; hover assist adds rotor lift to compensate it.
			var gravity=18.0
			var lift=gravity+clampf((vertical*12-velocity.y)*3,-10,10)
			velocity.y+=(lift-gravity)*dt
		else:
			velocity.x=move_toward(velocity.x,0,dt*4)
			velocity.z=move_toward(velocity.z,0,dt*4)
			velocity.y-=18.0*dt
		if position.y-mission.field.height_at(position.x,position.z)>1200: velocity.y=minf(velocity.y,0)
		if is_instance_valid(rotor): rotor.rotation.y+=dt*(28 if driven else 5)
		speed=Vector2(velocity.x,velocity.z).length()
		rotation.x=lerpf(rotation.x,clampf(input.y*0.12,-0.16,0.16),1-exp(-dt*3))
		rotation.z=lerpf(rotation.z,-input.x*0.12,1-exp(-dt*3))
	else:
		_suspension(dt)
		var traction=1.0 if suspension_contacts>=2 else 0.05
		var target=-input.y*(24 if kind=="JEEP" else 16)
		speed=move_toward(speed,target,dt*(8 if driven or ai_driven else 12)*traction)
		if driven and Input.is_action_pressed("jump"): speed=move_toward(speed,0,dt*25*traction)
		rotation.y-=input.x*dt*1.1*clampf(absf(speed)/4,0,1)*(1 if speed>=0 else -1)*traction
		var forward=-Basis(Vector3.UP,rotation.y).z
		velocity.x=forward.x*speed
		velocity.z=forward.z*speed
		logistics.tow_tick(dt)
		if logistics.parachute and suspension_contacts<2: velocity.y=maxf(velocity.y,-7)
		elif logistics.parachute:
			logistics.parachute=false
			if is_instance_valid(logistics.chute): logistics.chute.queue_free()
		wheel_spin+=speed*dt
		for wheel in wheels:
			wheel.pivot.rotation.y=-input.x*0.43 if wheel.front else 0.0
			wheel.roll.rotation.x=-wheel_spin/wheel.radius
	var impact_speed=velocity.y
	var before=velocity.length()
	move_and_slide()
	if impact_speed< -10 and is_on_floor(): take_damage((-impact_speed-10)*8)
	position.x=clampf(position.x,-mission.field.LIMIT+10,mission.field.LIMIT-10)
	position.z=clampf(position.z,-mission.field.LIMIT+10,mission.field.LIMIT-10)
	if before>18 and get_slide_collision_count()>0:
		for i in range(get_slide_collision_count()):
			if get_slide_collision(i).get_normal().dot(Vector3.UP)<0.4:
				take_damage(before*0.3)
				speed*=0.65
				break
	if position.y< -2.5: take_damage(45*dt)
	logistics.move_dependents(before_transform)
	logistics.tick()
	if mission.player.vehicle==self and mission.player.vehicle_seat>=0: mission.player.rotation.y+=wrapf(rotation.y-previous_yaw,-PI,PI)

func _plane_motion(dt: float,input: Vector2,driven: bool,ai_driven: bool) -> void:
	if driven and health>0: throttle=clampf(throttle-input.y*dt*0.35,0,1)
	elif ai_driven and health>0: throttle=0.7 if logistics.drive_order else 0.0
	else: throttle=0
	speed=move_toward(speed,throttle*100,dt*(8 if throttle>0 else 5))
	rotation.y-=input.x*dt*(0.42 if speed>30 else 0.7)*clampf(absf(speed)/5,0,1)
	var forward=-Basis(Vector3.UP,rotation.y).z
	velocity.x=forward.x*speed; velocity.z=forward.z*speed
	var vertical=0.0
	if driven:
		vertical=(1.0 if Input.is_action_pressed("jump") else 0.0)-(1.0 if Input.is_action_pressed("crouch") else 0.0)
	elif ai_driven and logistics.drive_order:
		vertical=clampf((mission.field.height_at(position.x,position.z)+100-position.y)/40,-1,1)
	if speed>30 and health>0:
		velocity.y=move_toward(velocity.y,vertical*14,dt*5)
	else: velocity.y-=18*dt
	if speed<12 and driven and Input.is_action_pressed("crouch"): throttle=0; speed=move_toward(speed,0,dt*15)
	rotation.x=lerpf(rotation.x,vertical*0.08,dt*2)
	rotation.z=lerpf(rotation.z,-input.x*0.15,dt*2)

func take_damage(amount: float) -> void:
	if health<=0: return
	health=maxf(health-amount,0)
	if health<=0:
		for actor in occupants.duplicate()+logistics.walkers.duplicate():
			if is_instance_valid(actor):
				exit_actor(actor,true)
				actor.take_damage(35)
		visuals.rotation.z=0.13
		mission.radio("Vehicle disabled. Dismount and take cover.")
