extends CharacterBody3D
const WeaponModel=preload("res://scripts/weapon_model.gd")
var mission: Node3D
var camera: Camera3D
var gun: Node3D
var health=100.0
var pitch=0.0
var sensitivity=0.0021
var kick=0.0
var flash_time=0.0
var walk_time=0.0
var crouched=false
var aiming=false
var sprinting=false
var stamina=1.0
var collision: CollisionShape3D
var loadout: Array[int]=[0,30,34]
var active_slot=0
var weapon: Dictionary={}
var switch_left=0.0
var vehicle: Node3D
var vehicle_seat=-1
var vehicle_external=false

func _ready() -> void:
	collision_layer=2
	collision_mask=15
	floor_snap_length=0.6
	collision=CollisionShape3D.new()
	var capsule=CapsuleShape3D.new()
	capsule.radius=0.32
	capsule.height=1.8
	collision.shape=capsule
	collision.position.y=0.9
	add_child(collision)
	camera=Camera3D.new()
	camera.position.y=1.64
	camera.far=36000
	camera.near=0.035
	camera.fov=78
	add_child(camera)
	camera.current=true
	gun=WeaponModel.new()
	gun.mission=mission
	gun.camera=camera
	camera.add_child(gun)
	loadout.assign(Settings.weapon_slots)
	equip_slot(0)

func equip_slot(slot: int) -> bool:
	if slot<0 or slot>2: return false
	if is_instance_valid(vehicle) and vehicle.mounted_weapon_id(vehicle_seat)>=0: return false
	active_slot=slot
	return equip_profile(loadout[slot])

func equip_profile(id: int) -> bool:
	if id<0 or id>=mission.weapon_profiles.size(): return false
	var spec: Dictionary=mission.weapon_profiles[id]
	if not mission.sim.equip_weapon(id,int(spec.capacity),float(spec.interval),float(spec.reload),int(spec.reserve)): return false
	weapon=spec
	switch_left=0.35
	gun.rebuild(weapon)
	return true

func assign_weapon(slot: int,id: int) -> bool:
	if slot<0 or slot>2 or id<0 or id>=mission.weapon_profiles.size(): return false
	if not mission.weapon_profiles[id].portable: return false
	loadout[slot]=id
	Settings.weapon_slots.assign(loadout)
	Settings.save_preferences()
	if slot==active_slot and not is_instance_valid(vehicle): equip_profile(id)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if mission.benchmark_mode or not mission.active(): return
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		var factor=clampf(float(weapon.zoom)/78,0.15,0.85) if aiming else 1.0
		rotate_y(-event.relative.x*sensitivity*factor)
		pitch=clampf(pitch-event.relative.y*sensitivity*factor,-1.45,1.45)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_V and is_instance_valid(vehicle):
		vehicle_external=not vehicle_external
	if event.is_action_pressed("reload"):
		if mission.sim.reload(): mission.audio.play_reload()

func _physics_process(dt: float) -> void:
	if not mission.active(): return
	mission.sim.tick_weapon(dt)
	switch_left=maxf(0,switch_left-dt)
	var armed=not is_instance_valid(vehicle) or vehicle.can_shoot(vehicle_seat)
	aiming=armed and ((Input.is_action_pressed("aim") and not mission.benchmark_mode) or mission.aim_preview)
	if is_instance_valid(vehicle) and vehicle_seat==-2:
		_move_on_foot(dt)
	elif is_instance_valid(vehicle):
		global_position=vehicle.seat_position(vehicle_seat)
		velocity=Vector3.ZERO
		crouched=false
		sprinting=false
	else:
		_move_on_foot(dt)
	if position.y < mission.field.height_at(position.x,position.z)-60: take_damage(100)
	if position.y < -1.5 and not is_instance_valid(vehicle): take_damage(18*dt)
	var trigger=Input.is_action_pressed("fire") if weapon.automatic else Input.is_action_just_pressed("fire")
	if trigger and armed and switch_left<=0 and not sprinting and not mission.benchmark_mode and (Input.mouse_mode==Input.MOUSE_MODE_CAPTURED or mission.integrated_test):
		if mission.sim.fire():
			mission.player_shot()
			kick+=float(weapon.recoil)*(0.6 if aiming else 1.0)
			pitch=clampf(pitch+float(weapon.recoil)*0.16,-1.45,1.45)
			flash_time=0.045
		elif mission.sim.weapon_state().rounds==0 and mission.sim.weapon_state().reload==0:
			mission.sim.reload()
	var eye=1.03 if crouched else 1.64
	camera.position.y=lerpf(camera.position.y,eye,dt*12)
	kick=move_toward(kick,0,dt*0.20)
	camera.position.x=0
	camera.position.z=0
	camera.rotation=Vector3(pitch+kick,0,0)
	if is_instance_valid(vehicle) and vehicle_seat!=-2:
		if vehicle_external and not aiming:
			var focus=global_position+Vector3.UP*1.4
			var desired=focus+global_basis*Vector3(0,2.5,45.0 if vehicle.kind=="CARGO" else (12.0 if vehicle.kind=="HELI" else 8.0))
			var query=PhysicsRayQueryParameters3D.create(focus,desired,1|8,[get_rid(),vehicle.get_rid()])
			var hit=get_world_3d().direct_space_state.intersect_ray(query)
			camera.global_position=desired if hit.is_empty() else hit.position+hit.normal*0.25
			camera.look_at(focus-global_basis.z*6,Vector3.UP)
		else:
			camera.rotation.x+=vehicle.rotation.x*0.65
			camera.rotation.z=vehicle.rotation.z*0.65
	camera.fov=lerpf(camera.fov,float(weapon.zoom) if aiming else (84.0 if sprinting else 78.0),dt*14)
	var moving=Vector2(velocity.x,velocity.z).length()
	walk_time+=dt*moving
	var bob=sin(walk_time*2.3)*0.006 if moving>0.1 and is_on_floor() else 0.0
	var ws: Dictionary=mission.sim.weapon_state()
	gun.pose(dt,aiming,kick,float(ws.reload)/float(ws.reload_duration),bob,flash_time>0)
	if not armed or (is_instance_valid(vehicle) and vehicle_seat!=-2 and vehicle_external and not aiming): gun.visible=false
	flash_time-=dt

func _move_on_foot(dt: float) -> void:
	crouched=Input.is_action_pressed("crouch") and not mission.benchmark_mode
	var shape=collision.shape as CapsuleShape3D
	if not crouched and shape.height<1.7:
		crouched=not mission.raycast(global_position+Vector3.UP,global_position+Vector3.UP*1.85,[get_rid()]).is_empty()
	shape.height=1.15 if crouched else 1.8
	collision.position.y=shape.height/2
	var input=Vector2.ZERO if mission.benchmark_mode else Input.get_vector("left","right","forward","back")
	sprinting=Input.is_action_pressed("sprint") and not crouched and not aiming and input.y< -0.2 and stamina>0.05
	stamina=clampf(stamina+dt*(-0.19 if sprinting else 0.13),0,1)
	var speed=6.6 if sprinting else (2.0 if crouched else (2.5 if aiming else 4.2))
	var direction=global_basis*Vector3(input.x,0,input.y)
	velocity.x=move_toward(velocity.x,direction.x*speed,dt*20)
	velocity.z=move_toward(velocity.z,direction.z*speed,dt*20)
	if not is_on_floor(): velocity.y-=20*dt
	else:
		velocity.y=-0.1
		if Input.is_action_just_pressed("jump") and not crouched and not mission.benchmark_mode: velocity.y=5.5
		# Step over thresholds and low doorsteps while keeping full wall collision.
		var horizontal=Vector3(velocity.x,0,velocity.z)*dt
		if horizontal.length()>0.001 and test_move(global_transform,horizontal):
			var raised=global_transform
			raised.origin.y+=0.38
			if not test_move(global_transform,Vector3.UP*0.38) and not test_move(raised,horizontal*2): position.y+=0.38
	move_and_slide()
	position.x=clampf(position.x,-mission.field.LIMIT+10,mission.field.LIMIT-10)
	position.z=clampf(position.z,-mission.field.LIMIT+10,mission.field.LIMIT-10)

func sightline_is_clear() -> bool:
	return gun.centre_clear()

func take_damage(amount: float) -> void:
	if mission.benchmark_mode or health<=0: return
	if is_instance_valid(vehicle) and vehicle.kind in ["APC","TANK"]: amount*=0.15
	health=maxf(0,health-amount)
	mission.damage_flash=1
	if health<=0: mission.finish(false)
