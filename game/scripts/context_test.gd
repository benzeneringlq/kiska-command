extends RefCounted
## Regression for user-observed crowd ejection, scoped orders and grounded exits.
var mission: Node3D
var checks=0
var failed=false
var stage=0
var clock=0
var plane: Node3D
var other: Node3D
var tank: Node3D
var truck: Node3D
var jeep: Node3D
var echo: Node3D
var origin=Vector3.ZERO
var platform: StaticBody3D

func check(ok: bool,label: String) -> void:
	if not ok:
		failed=true; push_error("CONTEXT_FAILED: "+label); mission.get_tree().quit(3)
	else: checks+=1; print("CONTEXT_CHECK: ",label)

func next() -> void:
	stage+=1; clock=0; print("CONTEXT_STAGE: ",stage)

func key(code: Key) -> void:
	var event=InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=true
	mission._unhandled_input(event)
	if code==KEY_Q and mission.q_held: mission.tick_q_gesture(0.3)

func detach(actor: Node3D) -> void:
	if is_instance_valid(actor.vehicle):
		if actor.vehicle_seat>=0: actor.vehicle.occupants[actor.vehicle_seat]=null
		actor.vehicle.logistics.walkers.erase(actor)
	actor.vehicle=null; actor.vehicle_seat=-1; actor.velocity=Vector3.ZERO
	actor.collision_layer=2 if actor==mission.player else 4; actor.collision_mask=15
	actor.platform_floor_layers=0xffffffff

func aim(point: Vector3) -> void:
	var p=mission.player
	p.camera.position=Vector3(0,1.64,0)
	var d=point-p.camera.global_position
	p.rotation.y=atan2(-d.x,-d.z); p.pitch=atan2(d.y,Vector2(d.x,d.z).length()); p.camera.rotation=Vector3(p.pitch,0,0)

func aim_at_side(target: Node3D) -> void:
	detach(mission.player)
	mission.teleport_player(target.to_global(Vector3(6.5,0,16)))
	aim(target.to_global(Vector3(4.9,4,15)))

func tick(_frame: int) -> void:
	if failed: return
	clock+=1
	var p=mission.player
	if stage==0 and clock==25:
		plane=mission.vehicles[11]; tank=mission.vehicles[10]; truck=mission.vehicles[9]; jeep=mission.vehicles[0]
		mission._spawn_actor(mission.field.spawn_position,true,33,"ECHO"); echo=mission.actors[-1]
		jeep.board(echo,1)
		plane.logistics.toggle_doors()
		tank.global_transform=plane.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.3,-5))
		tank.set_physics_process(false)
		for i in range(3): tank.board(mission.actors[i],i)
		check(tank.logistics.carrier==null,"manual-entry case starts without cached carrier registration")
		plane.logistics.walk_aboard(p,Vector3(3.45,1.28,8))
		mission.dismount_squad(tank)
		check(echo.vehicle==jeep,"targeted dismount does not eject occupants of another vehicle")
		for i in range(3):
			var actor=mission.actors[i]; actor.set_physics_process(true)
			check(actor.vehicle==plane and actor.vehicle_seat==-2,"crew dismount resolves actual containing aircraft: "+str(i))
		next()
	elif stage==1 and clock==120:
		for i in range(3):
			var actor=mission.actors[i]; var local=plane.to_local(actor.position)
			check(absf(local.x)<4.5 and absf(local.y-1.2)<0.3,"crew remains on the cargo floor after real collision frames: "+str(i))
			for j in range(i): check(actor.position.distance_to(mission.actors[j].position)>0.8,"crew exits reserve separate capsule-sized positions")
		aim(tank.position+Vector3.UP*1.1); key(KEY_Q)
		print("CONTEXT_AIM: ",mission.command_context," camera=",p.camera.global_position," tank=",tank.position)
		check(mission.command_context.get("vehicle")==tank,"Q captures the actual aimed tank")
		check(mission.command_options()==["BOARD","DISEMBARK","MOVE"],"vehicle context has only board, dismount and move")
		key(KEY_2)
		check(echo.vehicle==jeep,"Q dismount remains scoped to the frozen vehicle target")
		plane.logistics.release(tank); plane.logistics.cargo.erase(tank); tank.logistics.carrier=null
		detach(p); tank.board(p,0)
		check(tank.exit_actor(p),"player immediately dismounts manually loaded tank without waiting for registration")
		next()
	elif stage==2 and clock==80:
		check(p.vehicle==plane and absf(plane.to_local(p.position).y-1.2)<0.3,"player stays inside on the floor, not on roof or outside")
		other=mission._spawn_vehicle("CARGO",plane.position+Vector3(40,0,0))
		mission.field.ensure_area(other.position)
		mission.selected_vehicle=other
		aim_at_side(plane)
		check(mission.aimed_vehicle()==plane,"physical ramp control targets the near aimed aircraft")
		var before=plane.logistics.doors_open
		mission.logistics_action(KEY_G)
		check(plane.logistics.doors_open!=before and not other.logistics.doors_open,"G changes near aimed aircraft, ignoring remote J selection")
		mission.selected_vehicle=plane
		mission.teleport_player(plane.to_global(Vector3(8,0,75)))
		aim(plane.to_global(Vector3(4.9,5,16)))
		before=plane.logistics.doors_open; mission.logistics_action(KEY_G)
		check(plane.logistics.doors_open==before and mission.controlled_plane()==null,"far-away selection cannot operate aircraft doors")
		next()
	elif stage==3 and clock==20:
		aim_at_side(other)
		mission.selected_vehicle=plane
		print("SECOND_CONTROL: aim=",mission.aimed_vehicle()," control=",mission.controlled_plane()," p=",p.position," plane=",other.position)
		mission.logistics_action(KEY_G)
		check(other.logistics.doors_open,"G can operate a second actual aircraft instance")
		plane.logistics.walk_aboard(p)
		var before=other.logistics.doors_open
		mission.logistics_action(KEY_G)
		check(other.logistics.doors_open==before,"onboard control never changes a different aircraft")
		# Stop and leave on an actual collision-supported airframe.
		plane.speed=0; plane.velocity=Vector3.ZERO
		plane.board(p,0)
		if plane.logistics.doors_open: plane.logistics.toggle_doors()
		check(plane.exit_actor(p) and p.vehicle==plane and p.vehicle_seat==-2,"closed-ramp pilot dismount enters cargo bay instead of ejecting outside")
		mission.logistics_action(KEY_G)
		mission.use_vehicle()
		check(p.vehicle==null,"E leaves a stopped grounded aircraft through its open ramp")
		next()
	elif stage==4 and clock==80:
		check(p.vehicle==null and p.is_on_floor(),"aircraft exit remains on actual outside ground after physics settles")
		for i in range(3):
			var actor=mission.actors[i]; detach(actor)
			actor.position=mission.field.ground(plane.to_global(Vector3(i*2-2,0,40)),0.15)
		truck.global_transform=Transform3D(Basis.IDENTITY,mission.field.ground(plane.to_global(Vector3(0,0,38)),0.15))
		truck.velocity=Vector3.ZERO; truck.speed=0
		if plane.logistics.doors_open: plane.logistics.toggle_doors()
		mission.selected_vehicle=truck
		aim_at_side(plane)
		key(KEY_Q); key(KEY_3)
		check(truck.reservations.has(0),"move into aircraft assigns a missing driver automatically")
		check(truck.logistics.awaiting_ramp and not plane.logistics.doors_open,"load command queues approach without remotely opening the ramp")
		next()
	elif stage==5:
		if clock%180==0: print("CONTEXT_LOAD: ",plane.to_local(truck.position)," driver=",is_instance_valid(truck.occupants[0])," ramp=",plane.logistics.doors_open," route=",truck.logistics.route.size())
		if truck.logistics.secured:
			check(plane.logistics.doors_open and plane.logistics.inside(truck),"assigned driver approaches, opens the correct ramp and actually drives aboard")
			check(is_instance_valid(truck.occupants[0]),"automatic loading keeps the assigned driver aboard")
			# Elevation above the coarse terrain must not mean 'airborne'.
			for actor in mission.actors:
				if actor.vehicle==plane:
					detach(actor); actor.position=mission.field.ground(plane.position+Vector3(60,0,0),0.15); actor.set_physics_process(false)
			detach(p)
			platform=StaticBody3D.new(); mission.add_child(platform)
			var shape=CollisionShape3D.new(); var box=BoxShape3D.new(); box.size=Vector3(110,1,110); shape.shape=box; platform.add_child(shape)
			platform.position=mission.field.ground(plane.position,4.5)
			plane.position.y=platform.position.y+0.6; plane.speed=0; plane.velocity=Vector3.ZERO
			plane.board(p,0)
			next()
		elif clock>1800: check(false,"context automatic loading timed out")
	elif stage==6 and clock==90:
		check(plane.position.y-mission.field.height_at(plane.position.x,plane.position.z)>3.2 and plane.supported_and_stopped(),"raised but grounded aircraft is classified by actual support, not centre altitude")
		if not plane.logistics.doors_open: plane.logistics.toggle_doors()
		mission.use_vehicle()
		check(p.vehicle==null,"E exits a zero-speed supported aircraft above coarse terrain height")
		check(p.vehicle==null and absf(p.position.y-(platform.position.y+0.5))<0.3,"exit uses actual platform collision height, not island terrain sampling")
		detach(p); mission.teleport_player(jeep.position+Vector3(4,0,3))
		aim(jeep.position+Vector3.UP)
		key(KEY_Q); key(KEY_3)
		check(mission.map_open,"ordinary aimed vehicle move opens destination selection")
		check(jeep.occupants[0]==echo,"missing driver is filled from an existing passenger")
		origin=jeep.position
		var event=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
		event.position=mission.hud.map_point(jeep.position-Vector3(0,0,20))*mission.hud.view_scale
		mission.hud._input(event); mission.map_open=false; mission._sync_mouse()
		next()
	elif stage==7 and clock==120:
		check(jeep.position.distance_to(origin)>5,"map destination drives the automatically staffed vehicle")
		aim(jeep.position+Vector3.UP); key(KEY_Q); key(KEY_2)
		check(not jeep.logistics.drive_order,"targeted moving-vehicle dismount first cancels driving")
		next()
	elif stage==8 and clock==120:
		check(echo.vehicle==null and absf(jeep.speed)<0.5,"driver stops then completes the queued dismount")
		check(is_instance_valid(truck.occupants[0]),"targeted stop/dismount does not remove a different cargo driver")
		print("CONTEXT_PASS: ",checks," checks"); mission.audio.silence(); mission.get_tree().quit()
