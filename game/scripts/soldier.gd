extends CharacterBody3D
## Staggered sensing and path planning; physics movement remains at 60 Hz.
var mission: Node3D
var friendly = false
var call_sign = ""
var mind_id = 0
var health = 100.0
var visual: Node3D
var muzzle: Node3D
var command = "FOLLOW"
var command_target = Vector3.ZERO
var last_known = Vector3.ZERO
var spawn_point = Vector3.ZERO
var route = PackedVector3Array()
var path_index = 0
var plan_timer = 0.0
var sense_timer = 0.0
var fire_timer = 0.0
var target: Node3D
var priority_target: Node3D
var intent = 0
var visible_target = false
var awareness = 0.0
var walk_clock = 0.0
var limbs: Array[MeshInstance3D] = []
var status = "FOLLOW"
var corpse_timer = 0.0
var vehicle: Node3D
var vehicle_seat=-1
var boarding_target: Node3D
var boarding_seat=-1
var far_timer=0.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 15
	floor_snap_length = 0.6
	var capsule = CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.34
	var shape = CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	spawn_point = position
	last_known = position
	sense_timer = float(mind_id%5)*0.04
	plan_timer = float(mind_id%7)*0.09
	fire_timer = 0.3+float(mind_id%4)*0.2
	_build_visual()

func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var uniform: Material = mission.field.mat("friendly" if friendly else "hostile",Color(0.28,0.35,0.27) if friendly else Color(0.42,0.35,0.26))
	var vest: Material = mission.field.mat("vest",Color(0.17,0.21,0.17))
	var skin: Material = mission.field.mat("skin",Color(0.58,0.46,0.34))
	var dark: Material = mission.field.mat("rifle",Color(0.08,0.095,0.09))
	mission.field.box(visual,Vector3(0,1.1,0),Vector3(0.48,0.60,0.28),uniform)
	mission.field.box(visual,Vector3(0,1.13,-0.13),Vector3(0.42,0.44,0.14),vest)
	mission.field.box(visual,Vector3(0,1.60,0),Vector3(0.26,0.28,0.25),skin)
	mission.field.box(visual,Vector3(0,1.75,0.01),Vector3(0.32,0.15,0.31),uniform)
	for side in [-1,1]:
		limbs.append(mission.field.box(visual,Vector3(side*0.14,0.43,0),Vector3(0.19,0.77,0.22),uniform))
		mission.field.box(visual,Vector3(side*0.32,1.1,-0.12),Vector3(0.16,0.48,0.19),uniform)
	mission.field.box(visual,Vector3(0.17,1.2,-0.43),Vector3(0.07,0.10,0.62),dark)
	muzzle = Node3D.new()
	visual.add_child(muzzle)
	muzzle.position = Vector3(0.17,1.2,-0.78)
	if friendly:
		mission.field.box(visual,Vector3(0,1.96,0),Vector3(0.13,0.10,0.08),mission.field.mat("iff",Color(0.35,0.8,0.72)))

func _physics_process(dt: float) -> void:
	if not mission.active(): return
	if is_instance_valid(vehicle):
		if health<=0:
			vehicle.exit_actor(self,true)
			return
		if vehicle_seat==-2:
			visual.visible=true
			velocity.y=-0.1 if is_on_floor() else velocity.y-20*dt
			move_and_slide()
		else:
			global_position=vehicle.seat_position(vehicle_seat)
			visual.visible=vehicle_seat>0
		status="DRIVING" if vehicle_seat==0 and vehicle.kind!="HMG" else "ABOARD"
		if vehicle.can_shoot(vehicle_seat) and health>0:
			sense_timer-=dt; fire_timer-=dt
			if sense_timer<=0: _sense(0.2); sense_timer=0.2
			if visible_target and is_instance_valid(target) and fire_timer<=0:
				mission.actor_shot(self,target)
				fire_timer=0.16
		return
	var distance=position.distance_to(mission.player.position)
	visual.visible=distance<650
	if distance>250:
		collision_layer=0; collision_mask=0
		# Coarse off-screen squad travel avoids physics and pathfinding across 4 km.
		if friendly and health>0:
			far_timer+=dt
			if far_timer>=0.25:
				var goal: Vector3=mission.player.position if command=="FOLLOW" else command_target
				if is_instance_valid(boarding_target): goal=boarding_target.position
				position=mission.field.ground(position.move_toward(goal,2.2*far_timer),0.15)
				far_timer=0
		return
	if health>0: collision_layer=4; collision_mask=15
	if health <= 0:
		corpse_timer += dt
		return
	sense_timer -= dt
	plan_timer -= dt
	fire_timer -= dt
	if sense_timer <= 0:
		_sense(0.2)
		sense_timer = 0.2
	var destination = spawn_point
	var speed = 2.2
	if friendly:
		if is_instance_valid(boarding_target) and boarding_target.health<=0:
			boarding_target.reservations.erase(boarding_seat)
			boarding_target=null
			command="FOLLOW"
		status = command
		if command == "FOLLOW":
			var side = -1.0 if mind_id%2 == 0 else 1.0
			var offset = Vector3(side*(2.5+mind_id),0,3.5+mind_id*1.2)
			destination = mission.player.global_position+mission.player.global_basis*offset
		elif command == "HOLD": destination = command_target
		else: destination = command_target
		if destination.distance_to(global_position)<2.5: speed = 0
		if is_instance_valid(boarding_target):
			destination=boarding_target.to_global(Vector3(0,0,27)) if boarding_target.kind=="CARGO" else boarding_target.position+Vector3(3 if boarding_seat%2==0 else -3,0,1)
			status="BOARD"
			if boarding_target.access_distance(position)<5.0:
				boarding_target.board(self,boarding_seat)
				return
		if visible_target and not is_instance_valid(boarding_target):
			status = "CONTACT"
			if global_position.distance_to(target.global_position) < 38: speed = 0
	else:
		match intent:
			0:
				status = "PATROL"
				var t: float = mission.elapsed*0.10+mind_id*1.7
				destination = spawn_point+Vector3(sin(t)*4,0,cos(t)*4)
			1:
				status = "SEARCH"
				destination = last_known
			2:
				status = "ENGAGE"
				destination = last_known
				if visible_target and global_position.distance_to(last_known)<48: speed = 0
			3:
				status = "SUPPRESSED"
				destination = global_position
				speed = 0
	if visible_target and is_instance_valid(target):
		_face(target.global_position,dt)
		if fire_timer <= 0 and (friendly or intent == 2):
			mission.actor_shot(self,target)
			fire_timer = mission.rng.randf_range(0.30,0.65) if friendly else mission.rng.randf_range(0.7,1.25)
	if speed>0:
		if plan_timer<=0:
			route = mission.field.route(global_position,destination)
			path_index = 1 if route.size()>1 else 0
			plan_timer = 0.9+float(mind_id%4)*0.12
		while path_index < route.size() and Vector2(global_position.x-route[path_index].x,global_position.z-route[path_index].z).length()<0.7:
			path_index += 1
		if path_index<route.size():
			var d = route[path_index]-global_position
			d.y = 0
			d = d.normalized()
			# Local separation prevents a formation from collapsing onto one cell.
			var separation = Vector3.ZERO
			for other in mission.actors:
				if other == self or other.health<=0: continue
				var away: Vector3 = global_position-other.global_position
				away.y = 0
				if away.length_squared()<1.7 and away.length_squared()>0.01:
					separation += away.normalized()*0.8
			d = (d+separation).normalized()
			velocity.x = d.x*speed
			velocity.z = d.z*speed
			if not visible_target: _face(global_position+d,dt)
		else:
			velocity.x = 0
			velocity.z = 0
	else:
		velocity.x = move_toward(velocity.x,0,dt*12)
		velocity.z = move_toward(velocity.z,0,dt*12)
	velocity.y = -0.1 if is_on_floor() else velocity.y-20*dt
	move_and_slide()
	walk_clock += dt*Vector2(velocity.x,velocity.z).length()*3
	for i in range(limbs.size()): limbs[i].rotation.x = sin(walk_clock+i*PI)*0.35 if speed>0 else 0.0

func _face(p: Vector3, dt: float) -> void:
	var d = p-global_position
	if d.length_squared()>0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(-d.x,-d.z),dt*6)

func _sense(dt: float) -> void:
	var candidates: Array = []
	if friendly:
		for actor in mission.actors:
			if not actor.friendly and actor.health>0: candidates.append(actor)
		if is_instance_valid(priority_target) and priority_target.health>0:
			candidates.erase(priority_target)
			candidates.push_front(priority_target)
	else:
		candidates.append(mission.player)
		for actor in mission.actors:
			if actor.friendly and actor.health>0: candidates.append(actor)
	var best = 230.0 if friendly else 180.0
	target = null
	visible_target = false
	var eye = global_position+Vector3.UP*1.5
	for candidate in candidates:
		var distance: float = global_position.distance_to(candidate.global_position)
		if distance >= best: continue
		var to: Vector3 = candidate.global_position+Vector3.UP*(1.0 if candidate == mission.player and mission.player.crouched else 1.4)
		var dir = (to-eye).normalized()
		# Relax FOV after contact; quiet crouching reduces acquisition distance.
		if not friendly and awareness<0.4 and distance>12:
			if (-visual.global_basis.z).dot(dir)<0.1: continue
			if candidate == mission.player and mission.player.crouched and distance>95: continue
		var hit: Dictionary = mission.raycast(eye,to,[get_rid()])
		if hit.is_empty() or hit.get("collider") == candidate:
			target = candidate
			best = distance
			visible_target = true
			if friendly and candidate == priority_target: break
	if visible_target: last_known = target.global_position
	var heard: bool = not friendly and mission.noise_time>0 and global_position.distance_to(mission.noise_position)<65
	if heard and not visible_target: last_known = mission.noise_position
	if not friendly:
		var result: Dictionary = mission.sim.perceive(mind_id,dt,visible_target,best,heard)
		intent = result.intent
		awareness = result.awareness

func take_damage(amount: float) -> void:
	if health<=0: return
	health = maxf(health-amount,0)
	if health<=0:
		if is_instance_valid(boarding_target):
			boarding_target.reservations.erase(boarding_seat)
			boarding_target=null
		collision_layer = 0
		collision_mask = 0
		visual.rotation.z = PI/2
		visual.position.y = 0.1
		if friendly: mission.radio("%s is down. Keep moving.",[call_sign])
		else: mission.kills += 1
	else:
		mission.sim.suppress(mind_id,0.5)
