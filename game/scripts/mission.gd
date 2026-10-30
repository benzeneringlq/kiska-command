extends Node3D
const Battlefield=preload("res://scripts/battlefield.gd")
const Operator=preload("res://scripts/operator.gd")
const Soldier=preload("res://scripts/soldier.gd")
const Interface=preload("res://scripts/interface.gd")
const FieldAudio=preload("res://scripts/field_audio.gd")
const Vehicle=preload("res://scripts/tactical_vehicle.gd")
var field: Node3D
var player: CharacterBody3D
var actors: Array=[]
var vehicles: Array=[]
var weapon_profiles: Array=[]
var objectives: Array=[]
var objective_models: Array=[]
var objective_index=0
var sim: RefCounted
var hud: Control
var audio: Node
var rng=RandomNumberGenerator.new()
var state="BRIEFING"
var elapsed=0.0
var kills=0
var intel=false
var interact_progress=0.0
var extract_progress=0.0
var damage_flash=0.0
var hit_flash=0.0
var radio_text=""
var radio_arguments: Array=[]
var radio_timer=0.0
var noise_time=0.0
var noise_position=Vector3.ZERO
var map_open=false
var inventory_open=false
var command_open=false
var seat_menu: Node3D
var vehicle_menu=false
var selected_vehicle: Node3D
var command_context: Dictionary={}
var squad=preload("res://scripts/squad_director.gd").new()
var q_held=false
var q_elapsed=0.0
var q_menu_opened=false
var inventory_slot=0
var command_point=Vector3.ZERO
var command_marker_time=0.0
var bullets: Array[Dictionary]=[]
var effects: Array[Dictionary]=[]
var tracer_material: StandardMaterial3D
var phase="Village intelligence"
var smoke_test=false
var integrated_test=false
var test_frame=0
var test_runner: RefCounted
var render_frames=0
var capture_done=false
var benchmark_mode=false
var last_draw_usec=0
var capture_enabled=false
var aim_preview=false
var travel_benchmark=false
var benchmark_requested=false
var benchmark_started_ms=0
var focused_frames=0
var focused_seconds=0.0
var excluded_seconds=0.0
var previous_focus=false
var benchmark_finished=false
var focused_warmup=0

func _ready() -> void:
	rng.seed=1409
	squad.mission=self
	_setup_inputs()
	if not ClassDB.class_exists("TacticalSimulation"):
		push_error("Build the C++ extension with tools/build.sh before running.")
		get_tree().quit(2)
		return
	sim=ClassDB.instantiate("TacticalSimulation")
	weapon_profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons.json"))
	_setup_environment()
	field=Battlefield.new()
	field.mission=self
	add_child(field)
	audio=FieldAudio.new()
	add_child(audio)
	player=Operator.new()
	player.mission=self
	add_child(player)
	player.position=field.ground(field.spawn_position,0.15)
	for i in range(3): _spawn_actor(field.ground(field.spawn_position+Vector3(-4+i*4,0,5),0.15),true,i,["BRAVO","CHARLIE","DELTA"][i])
	for zone in range(1,6):
		for j in range(6):
			var p: Vector3=field.sites[zone].position+Vector3((-1 if j%2==0 else 1)*(12+j*3),0,(j/2-1)*14)
			_spawn_actor(field.ground(p,0.15),false,actors.size(),"GUARD")
	_setup_objectives()
	_spawn_vehicle("JEEP",field.spawn_position+Vector3(8,0,-5))
	_spawn_vehicle("APC",field.spawn_position+Vector3(-10,0,-25))
	_spawn_vehicle("HELI",field.spawn_position+Vector3(34,0,-35))
	_spawn_vehicle("JEEP",field.sites[1].position+Vector3(5,0,-35))
	_spawn_vehicle("APC",field.sites[5].position+Vector3(18,0,60))
	_spawn_vehicle("HELI",field.sites[5].position+Vector3(55,0,-110))
	for p in [field.sites[1].position+Vector3(10,0,-33),field.sites[3].position+Vector3(-15,0,-35),field.sites[5].position+Vector3(-15,0,40)]: _spawn_vehicle("HMG",p)
	_spawn_vehicle("TRUCK",field.spawn_position+Vector3(-22,0,15))
	_spawn_vehicle("TANK",field.spawn_position+Vector3(0,0,155))
	_spawn_vehicle("CARGO",field.spawn_position+Vector3(0,0,120))
	var layer=CanvasLayer.new()
	add_child(layer)
	hud=Interface.new()
	hud.mission=self
	layer.add_child(hud)
	tracer_material=StandardMaterial3D.new()
	tracer_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_material.albedo_color=Color(1.0,0.80,0.39)
	var args=OS.get_cmdline_user_args()
	benchmark_mode="--benchmark" in args or "--aim-showcase" in args or "--fullscreen-preview" in args or "--vehicle-showcase" in args or "--cargo-showcase" in args or "--cargo-interior-showcase" in args
	benchmark_requested="--benchmark" in args
	benchmark_started_ms=Time.get_ticks_msec()
	aim_preview="--aim-showcase" in args
	travel_benchmark="--travel-benchmark" in args
	capture_enabled="--capture" in args
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	smoke_test="--smoke-test" in args
	integrated_test="--integration-test" in args or "--logistics-test" in args or "--vehicle-context-test" in args or "--autonomy-test" in args
	squad.enabled=not integrated_test
	squad.auto_follow=not integrated_test
	if smoke_test or integrated_test: start()
	if integrated_test:
		for actor in actors: actor.set_physics_process(false)
		var fixture="res://scripts/autonomy_test.gd" if "--autonomy-test" in args else ("res://scripts/context_test.gd" if "--vehicle-context-test" in args else ("res://scripts/logistics_test.gd" if "--logistics-test" in args else "res://scripts/playtest.gd"))
		test_runner=load(fixture).new()
		test_runner.mission=self
	if "--showcase" in args:
		start()
		teleport_player(field.sites[1].position+Vector3(0,0,70))
		for actor in actors:
			if actor.friendly: actor.position=field.ground(player.position+Vector3((actor.mind_id-1)*3,0,4),0.15)
	if "--scope-showcase" in args: player.assign_weapon(0,25)
	if "--commands-showcase" in args:
		start()
		command_open=true
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if "--inventory-showcase" in args:
		start()
		inventory_open=true
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if "--map-showcase" in args:
		start()
		map_open=true
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if "--vehicle-showcase" in args:
		start()
		var index=2 if "--heli-preview" in args else (1 if "--apc-preview" in args else 0)
		vehicles[index].board(player)
		player.vehicle_external="--external-view" in args
		for actor in actors: actor.set_physics_process(false)
	if "--cargo-showcase" in args or "--cargo-interior-showcase" in args:
		start()
		var plane=vehicles[11]; var tank=vehicles[10]
		plane.logistics.toggle_doors()
		tank.global_transform=plane.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.35,3))
		plane.logistics.capture(tank,true)
		for actor in actors: actor.set_physics_process(false)
		if "--cargo-interior-showcase" in args:
			plane.logistics.walk_aboard(player,Vector3(3.2,1.25,13))
			player.rotation.y=0; player.pitch=0
		else:
			teleport_player(plane.to_global(Vector3(28,0,65)))
			var delta=plane.position+Vector3(0,6,0)-player.position
			player.rotation.y=atan2(-delta.x,-delta.z)
			player.pitch=atan2(delta.y,Vector2(delta.x,delta.z).length())
	if "--vehicle-command-showcase" in args:
		start()
		var target=vehicles[11]
		teleport_player(target.to_global(Vector3(6.5,0,16)))
		var delta=target.to_global(Vector3(4.9,4,15))-(player.position+Vector3.UP*1.64)
		player.rotation.y=atan2(-delta.x,-delta.z); player.pitch=atan2(delta.y,Vector2(delta.x,delta.z).length())
		command_context={"vehicle":target}; command_open=true; _sync_mouse()
	if "--seats-showcase" in args:
		start(); seat_menu=vehicles[11]; _sync_mouse()
	print("RIDGELINE_READY: Kiska 49152m region; real USGS relief; bounded terrain tiles; ",weapon_profiles.size()," weapons; ",actors.size()," soldiers; ",vehicles.size()," vehicles/emplacements")

func _setup_objectives() -> void:
	objectives=[
		{"title":"Village intelligence","position":field.ground(field.sites[1].position,0.8),"hold":1.8,"brief":"Recover the evacuation route at the harbor camp."},
		{"title":"Disable the relay","position":field.ground(field.sites[3].position,0.8),"hold":2.5,"brief":"Disable the relay terminal to cut hostile communications."},
		{"title":"Secure the airfield","position":field.ground(field.sites[5].position+Vector3(12,0,0),0.8),"hold":1.8,"brief":"Reach the airfield command post and transmit the all-clear."},
		{"title":"Northern extraction","position":field.extraction,"hold":3.0,"brief":"Rally at the northern beacon to complete the operation."}
	]
	for i in range(3):
		var size=Vector3(0.8,0.45,0.6) if i==0 else Vector3(1.2,1.6,0.8)
		var mesh=field.box(self,objectives[i].position,size,field.mat("objective",Color(0.85,0.58,0.21)),true)
		objective_models.append(mesh)

func _spawn_actor(pos: Vector3,friendly: bool,id: int,call_sign: String) -> void:
	var actor=Soldier.new()
	actor.mission=self
	actor.friendly=friendly
	actor.mind_id=id
	actor.call_sign=call_sign
	actor.position=pos
	actors.append(actor)
	add_child(actor)
	actor.visual.rotation.y=PI if not friendly else 0.0

func _spawn_vehicle(kind: String,p: Vector3) -> Node3D:
	var v=Vehicle.new()
	v.mission=self
	v.kind=kind
	v.position=field.ground(p,0.15)
	vehicles.append(v)
	add_child(v)
	return v

func teleport_player(p: Vector3) -> void:
	field.ensure_area(p)
	player.position=field.ground(p,0.2)
	player.velocity=Vector3.ZERO

func active() -> bool:
	if benchmark_requested and DisplayServer.get_name()!="headless" and not get_window().has_focus(): return false
	return state=="ACTIVE" and not map_open and not inventory_open and not command_open and not is_instance_valid(seat_menu) and not vehicle_menu

func start() -> void:
	state="ACTIVE"
	_sync_mouse()
	radio("OVERWATCH / Open the evacuation corridor: village, relay, then airfield. Transport is ready at staging.")

func _sync_mouse() -> void:
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if active() and not benchmark_mode else Input.MOUSE_MODE_VISIBLE

func toggle_inventory() -> void:
	if state!="ACTIVE": return
	inventory_open=not inventory_open
	command_open=false
	map_open=false
	inventory_slot=player.active_slot
	_sync_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if benchmark_mode: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if map_open or inventory_open or command_open or is_instance_valid(seat_menu) or vehicle_menu:
				map_open=false; inventory_open=false; command_open=false; seat_menu=null; vehicle_menu=false
			elif state=="ACTIVE": state="PAUSED"
			elif state=="PAUSED": state="ACTIVE"
			_sync_mouse()
			return
		if event.keycode==KEY_ENTER:
			if state=="BRIEFING": start()
			elif state=="PAUSED": state="ACTIVE"; _sync_mouse()
			elif state in ["SUCCESS","FAILED"]: get_tree().reload_current_scene()
			return
		if event.keycode==KEY_F3: hud.show_performance=not hud.show_performance
	if state!="ACTIVE": return
	if is_instance_valid(seat_menu) and event is InputEventKey and event.pressed and not event.echo:
		var index=int(event.physical_keycode)-int(KEY_1)
		if index>=0 and index<seat_menu.seat_count: choose_seat(index)
		elif index==seat_menu.seat_count and seat_menu.kind in ["TRUCK","CARGO"]: choose_seat(-2)
		return
	if event is InputEventKey and event.pressed and not event.echo and not inventory_open and not command_open and not map_open:
		if event.keycode==KEY_J:
			vehicle_menu=not vehicle_menu; _sync_mouse(); return
		if event.keycode==KEY_F:
			seat_menu=player.vehicle if is_instance_valid(player.vehicle) else nearest_vehicle(6)
			_sync_mouse(); return
		if active() and event.keycode in [KEY_G,KEY_L,KEY_O,KEY_T]:
			logistics_action(event.keycode); return
	if vehicle_menu: return
	if event.is_action_pressed("inventory"): toggle_inventory(); return
	if event.is_action("commands"):
		if event.is_pressed() and not event.is_echo():
			if command_open: command_open=false; q_held=false; _sync_mouse()
			elif active(): q_held=true; q_elapsed=0; q_menu_opened=false; capture_command_context()
		elif not event.is_pressed() and q_held:
			q_held=false
			if not q_menu_opened:
				if squad.enabled: squad.smart(command_context)
				else: command_open=true; _sync_mouse()
		return
	if event.is_action_pressed("map"):
		map_open=not map_open
		inventory_open=false; command_open=false
		_sync_mouse()
		return
	if command_open and event is InputEventKey and event.pressed and not event.echo:
		var index=int(event.physical_keycode)-int(KEY_1)
		if index>=0 and index<command_options().size(): select_command(index)
		return
	if inventory_open:
		if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_1,KEY_2,KEY_3]: inventory_slot=int(event.physical_keycode)-int(KEY_1)
		return
	if not active(): return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_1,KEY_2,KEY_3]: player.equip_slot(int(event.physical_keycode)-int(KEY_1))
	if event.is_action_pressed("interact"): use_vehicle()

func _setup_inputs() -> void:
	var keys={"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"reload":KEY_R,"crouch":KEY_C,"sprint":KEY_SHIFT,"jump":KEY_SPACE,"interact":KEY_E,"map":KEY_M,"inventory":KEY_B,"commands":KEY_Q}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var key=InputEventKey.new()
		key.physical_keycode=keys[action]
		InputMap.action_add_event(action,key)
	for pair in [["fire",MOUSE_BUTTON_LEFT],["aim",MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]): InputMap.add_action(pair[0])
		var mouse=InputEventMouseButton.new()
		mouse.button_index=pair[1]
		InputMap.action_add_event(pair[0],mouse)

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player): return
	if active():
		squad.tick(dt)
		if travel_benchmark:
			player.position.z=maxf(field.extraction.z,player.position.z-dt*140)
			player.position.x=field.road_x(player.position.z)+35
			player.position=field.ground(player.position,0.25)
			player.velocity=Vector3.ZERO
		field.stream_tick(player.position)
		elapsed+=dt
		damage_flash=maxf(0,damage_flash-dt*1.8)
		hit_flash=maxf(0,hit_flash-dt*5)
		radio_timer=maxf(0,radio_timer-dt)
		noise_time=maxf(0,noise_time-dt)
		command_marker_time=maxf(0,command_marker_time-dt)
		_tick_bullets(dt)
		_tick_effects(dt)
		_tick_objective(dt)
	if smoke_test or integrated_test:
		test_frame+=1
		if integrated_test: test_runner.tick(test_frame)
		elif test_frame==180:
			print("SMOKE_PASS: active_tiles=",field.chunks.size()," weapon=",player.weapon.name)
			get_tree().quit()

func _tick_objective(dt: float) -> void:
	if objective_index>=objectives.size(): return
	var objective: Dictionary=objectives[objective_index]
	phase=objective.title
	var close=player.position.distance_to(objective.position)<4.0 and not is_instance_valid(player.vehicle)
	if objective_index==3:
		extract_progress=extract_progress+dt if close else 0.0
		if extract_progress>=objective.hold: finish(true)
	elif close and Input.is_action_pressed("interact"):
		interact_progress+=dt
		if interact_progress>=objective.hold:
			objective_models[objective_index].material_override=field.mat("secured_objective",Color(0.22,0.52,0.43))
			objective_index+=1
			intel=true
			interact_progress=0
			phase=objectives[objective_index].title
			radio("OVERWATCH / Objective complete. Next: %s",[phase])
			audio.beep()
	else: interact_progress=maxf(0,interact_progress-dt*2)

func objective_position() -> Vector3:
	return objectives[mini(objective_index,objectives.size()-1)].position

func nearest_vehicle(range_metres: float=4.5,exclude: Node3D=null) -> Node3D:
	var best=range_metres
	var found: Node3D=null
	for v in vehicles:
		if v.health<=0 or v==exclude: continue
		var d=v.access_distance(player.position)
		if d<best: best=d; found=v
	return found

func use_vehicle() -> void:
	if is_instance_valid(player.vehicle) and player.vehicle_seat>=0:
		player.vehicle.exit_actor(player); return
	if player.position.distance_to(objective_position())<4.0: return
	var interior=player.vehicle
	if is_instance_valid(interior):
		var target=aimed_vehicle()
		if is_instance_valid(target) and target!=interior and target.access_distance(player.position)<=5:
			seat_menu=target; _sync_mouse()
		else: interior.exit_actor(player)
		return
	var v=nearest_vehicle(5)
	if is_instance_valid(v): seat_menu=v; _sync_mouse()

func choose_seat(seat: int) -> void:
	if not is_instance_valid(seat_menu): return
	var v=seat_menu
	var old=player.vehicle
	if is_instance_valid(old) and old!=v:
		if player.vehicle_seat!=-2: return
		old.logistics.walkers.erase(player); player.vehicle=null; player.vehicle_seat=-1
	var success=v.logistics.walk_aboard(player) if seat==-2 else v.board(player,seat)
	if not success:
		if is_instance_valid(old) and old!=v: old.logistics.walk_aboard(player)
		radio("Seat occupied or reserved."); return
	seat_menu=null; _sync_mouse()

func logistics_vehicle() -> Node3D:
	if is_instance_valid(selected_vehicle): return selected_vehicle
	if is_instance_valid(player.vehicle): return player.vehicle
	return nearest_vehicle(55)

func aimed_vehicle() -> Node3D:
	var excluded=[player.get_rid()]
	if is_instance_valid(player.vehicle): excluded.append(player.vehicle.get_rid())
	var hit=raycast(player.camera.global_position,player.camera.global_position-player.camera.global_basis.z*600,excluded)
	if not hit.is_empty() and hit.collider in vehicles: return hit.collider
	return null

func aim_context() -> Dictionary:
	var excluded=[player.get_rid()]
	if is_instance_valid(player.vehicle): excluded.append(player.vehicle.get_rid())
	var context=raycast(player.camera.global_position,player.camera.global_position-player.camera.global_basis.z*600,excluded)
	context["vehicle"]=context.get("collider") if context.get("collider") in vehicles else null
	return context

func capture_command_context() -> void:
	command_context=aim_context()

func command_options() -> Array:
	return ["BOARD","DISEMBARK","MOVE"] if is_instance_valid(command_context.get("vehicle")) else ["FOLLOW","HOLD","MOVE","ATTACK"]

func select_command(index: int) -> void:
	var options=command_options()
	if index<0 or index>=options.size(): return
	var command=options[index]
	var target=command_context.get("vehicle")
	command_open=false; q_held=false; _sync_mouse()
	if squad.enabled:
		if is_instance_valid(target):
			if command=="BOARD": squad.board(target)
			elif command=="DISEMBARK":
				if target.kind=="CARGO" and not target.logistics.cargo.is_empty(): squad.unload_transport(target)
				else: squad.dismount(target)
			elif target.kind=="CARGO": squad.load_transport(target)
			else: selected_vehicle=target; map_open=true; hud.map_zoom=true; _sync_mouse()
		elif command=="FOLLOW": squad.regroup()
		elif command=="HOLD": squad.hold()
		elif command_context.has("position"): squad.go(command_context.position,command_context.get("collider") if command=="ATTACK" else null)
	elif is_instance_valid(target):
		if command=="BOARD": board_squad(target)
		elif command=="DISEMBARK": dismount_squad(target)
		else: context_move(target)
	elif command=="MOVE" and command_context.has("position"): order_at("MOVE",command_context.position)
	else: order(command)
	command_context={}

func ensure_driver(source: Node3D) -> bool:
	if source.health<=0 or not source.logistics.ground_vehicle(): return false
	if is_instance_valid(source.occupants[0]):
		var driver=source.occupants[0]
		if driver==player: radio("Choose a passenger seat to delegate driving."); return false
		return driver.friendly and driver.health>0
	if source.reservations.has(0):
		var reserved=source.reservations[0]
		if is_instance_valid(reserved) and reserved.health>0: return true
		source.reservations.erase(0)
	var candidates=actors.filter(func(actor): return actor.friendly and actor.health>0 and (not is_instance_valid(actor.vehicle) or actor.vehicle==source or (actor.vehicle_seat!=0 and actor.vehicle.supported_and_stopped())))
	candidates.sort_custom(func(a,b): return a.position.distance_squared_to(source.position)<b.position.distance_squared_to(source.position))
	for driver in candidates:
		if driver.vehicle==source: return source.board(driver,0)
		var able=true
		for attempt in range(2):
			if not is_instance_valid(driver.vehicle): break
			var old=driver.vehicle
			if old.kind=="CARGO" and not old.logistics.doors_open: old.logistics.toggle_doors()
			if not old.exit_actor(driver): able=false; break
		if not able or is_instance_valid(driver.vehicle): continue
		if is_instance_valid(driver.boarding_target): driver.boarding_target.reservations.erase(driver.boarding_seat)
		source.reservations[0]=driver
		driver.boarding_target=source; driver.boarding_seat=0; driver.command="BOARD"; driver.plan_timer=0
		driver.set_physics_process(true)
		return true
	radio("No available squad driver."); return false

func command_source(destination: Node3D=null) -> Node3D:
	if is_instance_valid(selected_vehicle) and selected_vehicle!=destination and selected_vehicle.logistics.ground_vehicle() and not selected_vehicle.logistics.secured and (not is_instance_valid(destination) or selected_vehicle.logistics.carrier!=destination): return selected_vehicle
	if is_instance_valid(player.vehicle) and player.vehicle!=destination and player.vehicle.logistics.ground_vehicle() and not player.vehicle.logistics.secured and (not is_instance_valid(destination) or player.vehicle.logistics.carrier!=destination): return player.vehicle
	var best=60.0; var result: Node3D=null
	for source in vehicles:
		if source==destination or not source.logistics.ground_vehicle() or source.health<=0 or source.logistics.secured or (is_instance_valid(destination) and source.logistics.carrier==destination): continue
		var distance=source.position.distance_to(player.position)
		if distance<best: best=distance; result=source
	return result

func context_move(destination: Node3D) -> void:
	if destination.kind=="CARGO":
		var source=command_source(destination)
		if not is_instance_valid(source): radio("No ground vehicle nearby to load."); return
		if not ensure_driver(source): return
		selected_vehicle=source
		if source.logistics.request_loading(destination): radio("Driver will approach, open the ramp and load.")
		else: radio("Transport must be stopped and have cargo space.")
	else:
		selected_vehicle=destination
		if not ensure_driver(destination): return
		map_open=true; hud.map_zoom=true; _sync_mouse()
		radio("Choose a destination on the map, or aim at a transport and use Q3.")

func board_squad(target: Node3D) -> void:
	var assigned=0
	for actor in actors:
		if not actor.friendly or actor.health<=0: continue
		if is_instance_valid(actor.vehicle):
			if actor.vehicle==target and actor.vehicle_seat>0 and not is_instance_valid(target.occupants[0]) and not target.reservations.has(0):
				if target.board(actor,0): assigned+=1
			continue
		if is_instance_valid(actor.boarding_target): actor.boarding_target.reservations.erase(actor.boarding_seat)
		var seat=target.reserve(actor)
		if seat>=0:
			actor.boarding_target=target; actor.boarding_seat=seat; actor.command="BOARD"; actor.plan_timer=0
			actor.set_physics_process(true); assigned+=1
	radio("ALPHA / Board the transport. Seats assigned: %d",[assigned])

func dismount_squad(target: Node3D=null) -> void:
	for actor in actors:
		if not actor.friendly or not is_instance_valid(actor.vehicle) or (target!=null and actor.vehicle!=target): continue
		var current=actor.vehicle
		current.logistics.drive_order=false; current.logistics.route.clear(); current.logistics.awaiting_ramp=false
		if not current.exit_actor(actor) and actor not in current.logistics.dismount_requests: current.logistics.dismount_requests.append(actor)
	radio("ALPHA / Dismount and regroup.")

func controlled_plane() -> Node3D:
	# Physical controls never use the J selection or the frozen Q command target.
	var current=player.vehicle
	if is_instance_valid(current):
		if current.kind=="CARGO": return current
		var container=current.containing_transport()
		if is_instance_valid(container): return container
	for inside in vehicles:
		if inside.kind!="CARGO": continue
		var local=inside.to_local(player.position)
		if absf(local.x)<4.4 and local.z> -18 and local.z<17 and local.y>1.1 and local.y<6: return inside
	var target=aimed_vehicle()
	if not is_instance_valid(target) or target.kind!="CARGO": return null
	var distance=INF
	for point in [Vector3(0,1,26),Vector3(5.2,1.5,16),Vector3(-5,1,-22)]: distance=minf(distance,player.position.distance_to(target.to_global(point)))
	return target if distance<=8 else null

func nearby_plane(source: Node3D=null) -> Node3D:
	if is_instance_valid(source):
		if source.kind=="CARGO": return source
		if is_instance_valid(source.logistics.carrier): return source.logistics.carrier
	var best=150.0
	var result: Node3D=null
	for v in vehicles:
		if v.kind!="CARGO" or v.health<=0: continue
		var d=v.position.distance_to(source.position if is_instance_valid(source) else player.position)
		if d<best: result=v; best=d
	return result

func logistics_action(key: Key) -> void:
	var v=logistics_vehicle()
	if key==KEY_T and not is_instance_valid(v): radio("Select a vehicle with J."); return
	var plane=controlled_plane()
	if key==KEY_G:
		if is_instance_valid(plane) and plane.logistics.toggle_doors(): radio("Cargo ramp toggled.")
		else: radio("Ramp blocked or no transport nearby.")
	elif key==KEY_L:
		if is_instance_valid(plane) and plane.logistics.toggle_secure(): radio("Cargo restraints toggled.")
		else: radio("No vehicle fully inside the cargo bay.")
	elif key==KEY_O:
		if is_instance_valid(plane) and player.vehicle==plane and player.vehicle_seat==0 and plane.logistics.airdrop(): radio("Cargo released with parachutes.")
		else: radio("Open the ramp and load cargo first.")
	elif key==KEY_T:
		if is_instance_valid(v.logistics.tow_target): v.logistics.detach_tow(); radio("Tow cable detached."); return
		var best=18.0; var target: Node3D=null
		for other in vehicles:
			if other==v or not other.logistics.ground_vehicle() or is_instance_valid(other.occupants[0]): continue
			var d=v.position.distance_to(other.position)
			if d<best: best=d; target=other
		if is_instance_valid(target) and v.logistics.attach_tow(target): radio("Tow cable attached.")
		else: radio("Stop near an unoccupied ground vehicle to tow.")

func order(command: String) -> void:
	if command=="LOAD":
		var v=logistics_vehicle(); var plane=nearby_plane(v)
		if is_instance_valid(v) and is_instance_valid(plane) and v.logistics.load_into(plane): radio("Driver: loading vehicle into transport.")
		else: radio("Select a crewed ground vehicle; stop the transport and open its ramp.")
		return
	if command in ["SECURE","RAMP"]: logistics_action(KEY_L if command=="SECURE" else KEY_G); return
	if command=="DISEMBARK": dismount_squad(); return
	if command=="BOARD":
		var v=logistics_vehicle()
		if is_instance_valid(v): board_squad(v)
		else: radio("No transport within 45 metres.")
		return
	var destination: Vector3=player.position
	var designated: Node3D=null
	if command in ["MOVE","ATTACK"]:
		var origin=player.camera.global_position
		var excluded=[player.get_rid()]
		if is_instance_valid(player.vehicle): excluded.append(player.vehicle.get_rid())
		var hit=raycast(origin,origin-player.camera.global_basis.z*600,excluded)
		if hit.is_empty(): radio("Aim at ground or a hostile within 600 metres."); return
		destination=hit.position
		if hit.collider in actors and not hit.collider.friendly: designated=hit.collider
	order_at(command,destination,designated)

func order_at(command: String,destination: Vector3,designated: Node3D=null) -> void:
	if squad.enabled:
		if command=="FOLLOW": squad.regroup()
		elif command=="HOLD": squad.hold()
		else: squad.go(destination,designated if command=="ATTACK" else null)
		return
	if command=="MOVE":
		var source=selected_vehicle if is_instance_valid(selected_vehicle) else player.vehicle
		if is_instance_valid(source) and source.logistics.ground_vehicle():
			if ensure_driver(source): source.set_destination(destination); radio("Driver moving to the marked destination.")
			return
	command_point=destination
	command_marker_time=12
	for actor in actors:
		if not actor.friendly or actor.health<=0: continue
		if is_instance_valid(actor.vehicle):
			if actor.vehicle_seat==0 and (not is_instance_valid(selected_vehicle) or selected_vehicle==actor.vehicle):
				if command in ["MOVE","ATTACK","FOLLOW"]: actor.vehicle.set_destination(destination)
				elif command=="HOLD": actor.vehicle.logistics.drive_order=false; actor.vehicle.logistics.route.clear()
			continue
		if is_instance_valid(actor.boarding_target):
			actor.boarding_target.reservations.erase(actor.boarding_seat)
			actor.boarding_target=null
		actor.command=command
		actor.priority_target=designated
		actor.command_target=actor.position if command=="HOLD" else destination+Vector3((actor.mind_id-1)*2,0,2)
		actor.plan_timer=0
	radio("ALPHA / "+{"FOLLOW":"Regroup. Follow my lead.","HOLD":"Hold your positions. Cover the approach.","MOVE":"Move to the marked position.","ATTACK":"Advance and engage at the mark."}[command])
	audio.beep()

func radio(message: String,arguments: Array=[]) -> void:
	radio_text=message
	radio_arguments=arguments.duplicate()
	radio_timer=7

func localized_radio() -> String:
	var message=tr(radio_text)
	if radio_arguments.is_empty(): return message
	var translated: Array=[]
	for argument in radio_arguments:
		translated.append(tr(str(argument)) if argument is String or argument is StringName else argument)
	return message % translated

func raycast(from: Vector3,to: Vector3,exclude: Array=[]) -> Dictionary:
	var query=PhysicsRayQueryParameters3D.create(from,to,15)
	query.exclude=exclude
	return get_world_3d().direct_space_state.intersect_ray(query)

func player_shot() -> void:
	var spec: Dictionary=player.weapon
	var camera: Camera3D=player.camera
	var spread=float(spec.spread)*(1.0 if player.aiming else 3.0)
	if Vector2(player.velocity.x,player.velocity.z).length()>1: spread*=1.6
	for i in range(int(spec.pellets)):
		var direction=(-camera.global_basis.z+camera.global_basis.x*rng.randfn(0,spread)+camera.global_basis.y*rng.randfn(0,spread)).normalized()
		_spawn_bullet(camera.global_position,direction*float(spec.speed),player,true,spec)
	noise_position=player.position
	noise_time=0.8
	audio.play_shot()
	audio.local_player.pitch_scale*=0.75 if spec.category in ["Launcher","Sniper","Shotgun"] else (1.2 if spec.category=="SMG" else 1.0)

func actor_shot(actor: Node3D,target_actor: Node3D) -> void:
	if not is_instance_valid(target_actor) or target_actor.health<=0: return
	var origin: Vector3=actor.position+Vector3.UP*1.35
	var aim: Vector3=target_actor.position+Vector3.UP*1.1
	if target_actor==player and player.crouched: aim.y-=0.4
	var error=0.012 if actor.friendly else 0.024
	var direction=(aim-origin).normalized()+Vector3(rng.randfn(0,error),rng.randfn(0,error),rng.randfn(0,error))
	var spec: Dictionary=weapon_profiles[1 if actor.friendly else 3]
	if is_instance_valid(actor.vehicle) and actor.vehicle.mounted_weapon_id(actor.vehicle_seat)>=0: spec=weapon_profiles[35]
	_spawn_bullet(origin,direction.normalized()*float(spec.speed),actor,false,spec)
	audio.play_at(origin)

func _spawn_bullet(pos: Vector3,velocity: Vector3,owner_node: Node3D,from_player: bool,spec: Dictionary={}) -> void:
	if spec.is_empty(): spec=weapon_profiles[0]
	if bullets.size()>=256: bullets.pop_front()
	bullets.append({"position":pos,"origin":pos,"velocity":velocity,"owner":owner_node,"age":0.0,"player":from_player,"damage":float(spec.damage),"blast":float(spec.blast),"ttl":clampf(1800.0/velocity.length(),2.5,12.0)})

func _tick_bullets(dt: float) -> void:
	for i in range(bullets.size()-1,-1,-1):
		var b=bullets[i]
		var step: Array=sim.ballistic_step(b.position,b.velocity,dt)
		var new_pos: Vector3=step[0]
		var excluded=[b.owner.get_rid()]
		if is_instance_valid(b.owner.vehicle): excluded.append(b.owner.vehicle.get_rid())
		var hit=raycast(b.position,new_pos,excluded)
		var end: Vector3=hit.position if not hit.is_empty() else new_pos
		if b.age<0.07: _tracer(b.position,end)
		for actor in actors:
			if actor==b.owner or actor.health<=0 or not actor.visual.visible: continue
			var near=Geometry3D.get_closest_point_to_segment(actor.position+Vector3.UP,b.position,end)
			if near.distance_to(actor.position+Vector3.UP)<2.2: sim.suppress(actor.mind_id,dt*2)
		if not hit.is_empty():
			var collider: Object=hit.collider
			if collider.has_method("take_damage"):
				var headshot=collider in actors and hit.position.y-collider.global_position.y>1.43
				collider.take_damage(sim.damage(b.origin.distance_to(end),headshot)/49.0*b.damage)
				if b.player: hit_flash=1
			if b.blast>0: _explode(end+hit.normal*0.15,b.blast,b.damage,b.owner)
			else:
				var spark=field.box(self,end,Vector3(0.07,0.07,0.07),tracer_material)
				effects.append({"node":spark,"left":0.12})
			bullets.remove_at(i)
			continue
		b.position=new_pos; b.velocity=step[1]; b.age+=dt
		if b.age>b.ttl: bullets.remove_at(i)

func _explode(pos: Vector3,radius: float,damage: float,owner_node: Node3D) -> void:
	var targets=actors.duplicate()
	targets.append(player)
	targets.append_array(vehicles)
	for target in targets:
		if target.health<=0: continue
		var to: Vector3=target.position+Vector3.UP
		var distance=pos.distance_to(to)
		if distance>radius: continue
		var hit=raycast(pos,to,[])
		if hit.is_empty() or hit.collider==target: target.take_damage(damage*(1-distance/radius))
	var sphere=MeshInstance3D.new()
	var mesh=SphereMesh.new()
	mesh.radius=0.5; mesh.height=1
	sphere.mesh=mesh; sphere.material_override=tracer_material
	add_child(sphere); sphere.position=pos
	effects.append({"node":sphere,"left":0.22,"expand":radius*12})

func _tracer(from: Vector3,to: Vector3) -> void:
	var length=from.distance_to(to)
	if length<0.02: return
	var mesh=field.box(self,(from+to)*0.5,Vector3(0.012,0.012,minf(length,5)),tracer_material)
	mesh.look_at(to)
	effects.append({"node":mesh,"left":0.055})

func _tick_effects(dt: float) -> void:
	for i in range(effects.size()-1,-1,-1):
		effects[i].left-=dt
		if effects[i].has("expand"): effects[i].node.scale+=Vector3.ONE*effects[i].expand*dt
		if effects[i].left<=0: effects[i].node.queue_free(); effects.remove_at(i)

func finish(success: bool) -> void:
	state="SUCCESS" if success else "FAILED"
	_sync_mouse()
	audio.beep()

func _setup_environment() -> void:
	var env=WorldEnvironment.new()
	var e=Environment.new()
	e.background_mode=Environment.BG_SKY
	var sky=Sky.new()
	var atmosphere=ProceduralSkyMaterial.new()
	atmosphere.sky_top_color=Color(0.26,0.41,0.52)
	atmosphere.sky_horizon_color=Color(0.72,0.74,0.68)
	atmosphere.ground_bottom_color=Color(0.27,0.30,0.23)
	atmosphere.ground_horizon_color=Color(0.67,0.69,0.63)
	sky.sky_material=atmosphere; e.sky=sky
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color=Color(0.64,0.71,0.75); e.ambient_light_energy=0.35
	e.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	e.fog_enabled=true; e.fog_light_color=Color(0.58,0.65,0.64); e.fog_density=0.00012
	env.environment=e; add_child(env)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-39,-32,0); sun.light_color=Color(1,0.91,0.72)
	sun.light_energy=0.85; sun.shadow_enabled=true; sun.directional_shadow_max_distance=130
	add_child(sun)

func _on_frame_drawn() -> void:
	var now=Time.get_ticks_usec()
	render_frames+=1
	var focused=get_window().has_focus()
	if last_draw_usec>0:
		var duration=float(now-last_draw_usec)/1000000
		if focused and previous_focus:
			if focused_warmup<60: focused_warmup+=1
			else:
				focused_frames+=1
				focused_seconds+=duration
		else: excluded_seconds+=duration
	previous_focus=focused
	last_draw_usec=now
	if capture_enabled and render_frames==(240 if benchmark_mode else 90): _capture_frame.call_deferred()
	if benchmark_requested and focused_frames>=600: _finish_benchmark(false)

func tick_q_gesture(dt: float) -> void:
	if not q_held or q_menu_opened: return
	if state!="ACTIVE" or inventory_open or map_open or vehicle_menu or is_instance_valid(seat_menu):
		q_held=false; q_elapsed=0; return
	q_elapsed+=dt
	if q_elapsed>=0.28:
		q_menu_opened=true; command_open=true; inventory_open=false; map_open=false; _sync_mouse()

func _process(_dt: float) -> void:
	tick_q_gesture(_dt)
	# Background/minimized windows must not turn an unattended run into fake FPS.
	if benchmark_requested and not benchmark_finished and Time.get_ticks_msec()-benchmark_started_ms>30000:
		_finish_benchmark(true)

func _finish_benchmark(partial: bool) -> void:
	if benchmark_finished: return
	benchmark_finished=true
	var fps=snappedf(float(focused_frames)/focused_seconds,0.1) if focused_seconds>0 else 0.0
	print("RENDER_BENCHMARK_PARTIAL: " if partial else "RENDER_BENCHMARK: ","focused_frames=",focused_frames," mean_fps=",fps," excluded_unfocused_seconds=",snappedf(excluded_seconds,0.1)," image_pixels=",get_viewport().get_texture().get_image().get_size()," tiles=",field.chunks.size()," state=",state," streamed=",field.streamed_tiles," peak_tile_ms=",snappedf(field.peak_stream_ms,0.1)," camera_sweep=",travel_benchmark)
	get_tree().quit()

func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var args=OS.get_cmdline_user_args()
	var file="user://ridgeline-field.png" if "--showcase" in args else "user://ridgeline-menu.png"
	if map_open: file="user://ridgeline-map.png"
	if inventory_open: file="user://ridgeline-inventory.png"
	if command_open: file="user://ridgeline-orders.png"
	if "--cargo-showcase" in args: file="user://ridgeline-cargo.png"
	if "--cargo-interior-showcase" in args: file="user://ridgeline-cargo-interior.png"
	if "--seats-showcase" in args: file="user://ridgeline-seats.png"
	if aim_preview: file="user://ridgeline-aim.png"
	if "--vehicle-showcase" in args: file="user://ridgeline-vehicle-"+player.vehicle.kind.to_lower()+("-external" if player.vehicle_external else "-cab")+".png"
	if "--scope-showcase" in args: file="user://ridgeline-scope.png"
	var result=get_viewport().get_texture().get_image().save_png(file)
	print("CAPTURE: ",ProjectSettings.globalize_path(file)," status=",result)
	print("DISPLAY_CAPTURE: mode=",get_window().mode," window=",get_window().size," locale=",TranslationServer.get_locale()," centre_clear=",player.sightline_is_clear() if player.aiming else "n/a")
	capture_done=true
	if "--capture-and-exit" in args:
		if "--fullscreen-preview" in args: Settings.toggle_fullscreen()
		audio.silence(); get_tree().quit()
