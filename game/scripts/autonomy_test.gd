extends RefCounted
## Real input/physics acceptance tests for complete intents, not individual buttons.
var mission: Node3D
var checks=0
var failed=false
var stage=0
var clock=0
var plane: Node3D
var tank: Node3D
var jeep: Node3D
var truck: Node3D
var phases: Dictionary={}
var expected_serial=0
var origin=Vector3.ZERO

func check(ok: bool,label: String) -> void:
	if not ok: failed=true; push_error("AUTONOMY_FAILED: "+label); mission.get_tree().quit(3)
	else: checks+=1; print("AUTONOMY_CHECK: ",label)

func next() -> void:
	stage+=1; clock=0; print("AUTONOMY_STAGE: ",stage)

func q(pressed: bool) -> void:
	var event=InputEventKey.new(); event.physical_keycode=KEY_Q; event.keycode=KEY_Q; event.pressed=pressed
	mission._unhandled_input(event)

func key(code: Key) -> void:
	var event=InputEventKey.new(); event.physical_keycode=code; event.keycode=code; event.pressed=true
	mission._unhandled_input(event)

func aim(point: Vector3) -> void:
	var p=mission.player; p.camera.position=Vector3(0,1.64,0)
	var d=point-p.camera.global_position; p.rotation.y=atan2(-d.x,-d.z)
	p.pitch=atan2(d.y,Vector2(d.x,d.z).length()); p.camera.rotation=Vector3(p.pitch,0,0)

func tap() -> void:
	q(true); q(false)

func tick(_frame: int) -> void:
	if failed: return
	clock+=1
	var director=mission.squad
	var p=mission.player
	if not director.goal.is_empty(): phases[director.goal.phase]=true
	if stage==0 and clock==30:
		director.enabled=true; director.auto_follow=false
		plane=mission.vehicles[11]; tank=mission.vehicles[10]; jeep=mission.vehicles[0]; truck=mission.vehicles[9]
		for i in range(3):
			var actor=mission.actors[i]; actor.position=mission.field.ground(tank.position+Vector3(i*2-2,0,3),0.15); actor.set_physics_process(true)
		mission.teleport_player(plane.to_global(Vector3(6.5,0,16)))
		aim(plane.to_global(Vector3(4.9,4,15)))
		check(not plane.logistics.doors_open and not is_instance_valid(tank.occupants[0]),"scenario begins with closed ramp, no driver and no seat selections")
		tap()
		check(not mission.command_open and not mission.map_open,"quick Q executes intent without opening a menu or map")
		check(director.goal.get("kind")=="LOAD" and director.goal.source==tank,"quick Q infers the nearby tank for transport loading")
		expected_serial=director.serial; next()
	elif stage==1:
		if clock%240==0: print("AUTO_LOAD: ",director.status," phase=",director.goal.get("phase")," local=",plane.to_local(tank.position))
		if director.outcome=="BLOCKED": check(false,"automatic load blocked: "+director.status)
		elif director.outcome=="SUCCESS":
			check(director.serial==expected_serial,"one command completes the entire load workflow")
			check(tank.logistics.secured and tank.logistics.carrier==plane,"tank is physically loaded and restrained")
			check(not plane.logistics.doors_open,"squad closes the ramp automatically after securing cargo")
			check(mission.actors.slice(0,3).all(func(a): return a.vehicle==tank),"driver and passengers are all aboard without individual orders")
			check(phases.has("BOARDING") and phases.has("LOADING"),"task exposes actual boarding and loading progress")
			aim(plane.to_global(Vector3(4.9,4,15))); tap()
			check(director.goal.get("kind")=="UNLOAD","when no outside transport is available Q infers unload intent")
			expected_serial=director.serial; next()
		elif clock>2200: check(false,"load timeout")
	elif stage==2:
		if clock%180==0: print("AUTO_UNLOAD: ",director.status," phase=",director.goal.get("phase")," local=",plane.to_local(tank.position)," speed=",tank.speed)
		if director.outcome=="BLOCKED": check(false,"automatic unload blocked: "+director.status)
		elif director.outcome=="SUCCESS":
			check(director.serial==expected_serial,"one unload command completes the entire reverse-and-dismount workflow")
			check(plane.to_local(tank.position).z>35 and not is_instance_valid(tank.logistics.carrier),"driver physically reverses the tank out of the bay")
			check(not tank.logistics.secured and not plane.logistics.doors_open,"unloading releases restraints and closes ramp afterward")
			check(mission.actors.slice(0,3).all(func(a): return a.vehicle==null and a.command=="HOLD"),"crew dismounts and covers the unloading area automatically")
			mission.selected_vehicle=null
			var target=mission.field.ground(plane.to_global(Vector3(14,0,62)))
			aim(target); tap()
			check(director.goal.get("kind")=="GO","quick Q at ground creates a move-and-cover task")
			next()
		elif clock>1800: check(false,"unload timeout")
	elif stage==3:
		if director.outcome=="SUCCESS":
			check(director.status=="Position secured","squad reaches the foot destination and holds it")
			director.board(truck); next()
		elif director.outcome=="BLOCKED" or clock>900: check(false,"move-and-cover did not finish: "+director.status)
	elif stage==4 and clock==20:
		check(not director.goal.is_empty() and truck.reservations.size()>0,"a replacement task owns real boarding reservations")
		aim(mission.field.ground(p.position+Vector3(8,0,8)))
		var serial_before=director.serial
		q(true); key(KEY_B); mission.tick_q_gesture(0.3)
		check(not mission.q_held and not mission.command_open,"opening inventory cancels a pending Q gesture")
		key(KEY_B); q(false)
		check(director.serial==serial_before,"cancelled Q gesture cannot issue a hidden task on release")
		q(true)
		check(not mission.command_open,"Q press alone does not immediately pause play")
		next()
	elif stage==5 and clock==22:
		check(mission.command_open,"holding Q opens the detailed command menu")
		q(false); key(KEY_2)
		check(director.goal.is_empty() and director.mode=="HOLD","hold order cancels the active high-level task")
		check(truck.reservations.is_empty() and mission.actors.slice(0,3).all(func(a): return a.boarding_target!=truck),"cancelling clears reservations and old boarding actions")
		director.regroup(); director.auto_follow=true
		mission.teleport_player(jeep.position+Vector3(4,0,2))
		for i in range(3): mission.actors[i].position=mission.field.ground(jeep.position+Vector3(i*2-2,0,3),0.15)
		check(jeep.board(p,1),"player independently chooses a passenger seat")
		next()
	elif stage==6 and clock==120:
		check(mission.actors.slice(0,3).all(func(a): return a.vehicle==jeep),"followers board with the player without a Q order")
		check(jeep.occupants[0]==mission.actors[0],"followers automatically fill the driver slot")
		check(jeep.exit_actor(p),"player independently leaves the vehicle")
		next()
	elif stage==7 and clock==120:
		check(mission.actors.slice(0,3).all(func(a): return a.vehicle==null),"followers dismount after the player without another order")
		director.auto_follow=false
		plane.speed=10
		director.start("LOAD",tank,plane)
		next()
	elif stage==8 and clock==15:
		check(director.outcome=="BLOCKED" and director.status=="Transport must land and stop first","unsafe transport state is reported instead of requesting more micromanagement")
		check(not plane.logistics.doors_open,"blocked task does not remotely open the aircraft")
		plane.speed=0; director.cancel()
		mission.selected_vehicle=null
		key(KEY_M); mission.hud.map_zoom=true
		var click=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true
		click.position=mission.hud.map_point(jeep.position-Vector3(0,0,165))*mission.hud.view_scale
		mission.hud._input(click); mission.map_open=false; mission._sync_mouse()
		check(director.goal.get("source")==jeep,"long-distance map intent chooses nearby transport without J or individual orders")
		expected_serial=director.serial; next()
	elif stage==9:
		if director.outcome=="BLOCKED": check(false,"automatic transport trip blocked: "+director.status)
		elif director.outcome=="SUCCESS":
			check(director.serial==expected_serial,"one destination request completes boarding, driving and dismounting")
			check(mission.actors.slice(0,3).all(func(a): return a.vehicle==null),"crew dismounts automatically at the unattended destination")
			for i in range(3):
				var actor=mission.actors[i]; actor.position=mission.field.ground(jeep.position+Vector3(i*2-2,0,3),0.15); jeep.board(actor,i)
			mission.teleport_player(jeep.position+Vector3(4,0,3))
			mission.selected_vehicle=jeep
			director.go(jeep.position-Vector3(0,0,40)); next()
		elif clock>2200: check(false,"automatic transport trip timed out")
	elif stage==10 and not director.goal.is_empty() and director.goal.phase=="DRIVING":
		jeep.set_physics_process(false); next()
	elif stage==11:
		if director.outcome=="BLOCKED":
			check(director.status=="Command blocked: route or ramp obstructed","a genuinely stuck task reports its reason")
			check(not jeep.logistics.drive_order and director.goal.is_empty(),"blocked task releases the driver and clears stale action state")
			print("AUTONOMY_PASS: ",checks," checks"); mission.audio.silence(); mission.get_tree().quit()
		elif clock>1100: check(false,"stuck task did not terminate")
