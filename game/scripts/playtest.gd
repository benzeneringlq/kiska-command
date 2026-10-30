extends RefCounted
## Actual-engine regression fixture; the game is driven through its real systems.
var mission: Node3D
var checks=0
var failed=false
var saved_rounds=0
var hip_width=0.0
var jeep_start=Vector3.ZERO
var house: Dictionary
var ramp: StaticBody3D
var drop_height=0.0
var heli_drop_height=0.0

func check(condition: bool,label: String) -> void:
	if not condition:
		failed=true
		push_error("INTEGRATION_FAILED: "+label)
		mission.get_tree().quit(3)
	else:
		checks+=1
		print("CHECK: ",label)

func key(code: Key) -> void:
	var event=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	mission._unhandled_input(event)
	if code==KEY_Q and mission.q_held: mission.tick_q_gesture(0.3)

func width() -> float:
	var mesh: MeshInstance3D=mission.player.gun.get_child(0)
	var a: AABB=mesh.get_aabb()
	var left=mission.player.camera.unproject_position(mesh.to_global(a.position))
	var right=mission.player.camera.unproject_position(mesh.to_global(a.position+Vector3(a.size.x,0,0)))
	return absf(right.x-left.x)

func tick(frame: int) -> void:
	if failed: return
	var p=mission.player
	var sim=mission.sim
	if frame==20:
		check(mission.field.LIMIT==24576.0,"49.152 km Kiska region bounds")
		check(mission.field.relief.samples.size()==1025*1025,"offline real elevation raster loaded")
		check(mission.field.height_at(10429,-13768)>1100,"Kiska volcano retains its real elevation")
		check(mission.field.height_at(-20000,-20000)<0,"open ocean is below sea level")
		check(mission.field.middle_chunks.size()<=9,"middle terrain stays within nine tiles")
		check(mission.field.chunks.size()<=9,"initial detailed terrain stays within nine tiles")
		check(mission.field.houses.size()==28,"28 enterable small houses planned")
		check(mission.actors.size()==33,"three squadmates and thirty garrison soldiers")
		check(mission.weapon_profiles.size()==36,"36 weapon profiles loaded")
		check(mission.vehicles.size()==12,"transports, helicopters and fixed guns spawned")
		check(p.is_on_floor(),"streamed terrain provides player collision")
		Input.action_press("fire")
	elif frame==27:
		Input.action_release("fire")
		check(sim.weapon_state().rounds<30,"player fire input consumes native ammunition")
	elif frame==30:
		for spec in mission.weapon_profiles:
			check(sim.equip_weapon(int(spec.id),int(spec.capacity),float(spec.interval),float(spec.reload),int(spec.reserve)),"native profile config: "+spec.name)
			check(sim.weapon_state().capacity==int(spec.capacity),"native magazine matches: "+spec.name)
			# Existing rifle ammunition persists; never resets merely by changing weapons.
			sim.tick_weapon(10)
			check(sim.fire(),"native firing: "+spec.name)
		p.equip_slot(0)
		saved_rounds=sim.weapon_state().rounds
		p.equip_slot(1); p.equip_slot(0)
		check(sim.weapon_state().rounds==saved_rounds,"switching weapons preserves magazine state")
		check(not sim.equip_weapon(100,0,0.1,2.0,10),"invalid native weapon capacity rejected")
		key(KEY_B)
		check(mission.inventory_open and not mission.active(),"B opens backpack and pauses combat")
		check(p.assign_weapon(1,25),"backpack assigns an unlocked sniper to slot two")
		check(not p.assign_weapon(2,35),"fixed HMG cannot be placed in a carried slot")
		key(KEY_B)
		check(not mission.inventory_open and mission.active(),"B returns to combat")
		key(KEY_Q)
		check(mission.command_open and not mission.active(),"Q opens the command menu")
		key(KEY_2)
		check(not mission.command_open and mission.actors[0].command=="HOLD","Q then 2 issues hold instead of switching weapons")
		key(KEY_2)
		check(p.active_slot==1 and p.weapon.name=="AWM","2 outside Q selects weapon slot two")
		Input.action_press("aim")
		house=mission.field.houses[0]
		mission.teleport_player(house.position+Vector3(0,0,house.size.y/2+1.3))
		p.rotation.y=0
		Input.action_press("forward")
	elif frame==70:
		check(p.aiming and p.camera.fov<18,"scoped sniper uses its own magnification")
		check(not p.gun.visible and p.sightline_is_clear(),"scope removes obstructing viewmodel")
		p.equip_slot(0)
	elif frame==100:
		Input.action_release("forward")
		check(p.position.z<house.position.z+house.size.y/2-0.1,"player walks through doorway; position %s, doorway z %.2f" % [p.position,house.position.z+house.size.y/2])
		check(p.aiming and p.camera.fov>62 and p.camera.fov<66,"reflex sight has its own FOV")
		check(p.sightline_is_clear(),"open reflex aperture leaves the actual centre ray clear")
		mission.radio("ALPHA / Board the transport. Seats assigned: %d",[3])
		check(mission.localized_radio().contains("3"),"numeric radio parameters stay numeric during translation")
		Input.action_release("aim")
	elif frame==145:
		hip_width=width()
		Input.action_press("aim")
	elif frame==175:
		check(absf(width()-hip_width)<2.5,"world zoom does not enlarge the weapon model")
		Input.action_release("aim")
		house=mission.field.houses[0]
		mission.teleport_player(house.position+Vector3(0,0,house.size.y/2+3))
	elif frame==185:
		var base: Vector3=mission.field.ground(house.position)
		var front=base+Vector3(0,1.5,house.size.y/2+2)
		var inside=base+Vector3(0,1.5,0)
		check(mission.raycast(front,inside,[]).is_empty(),"house doorway is a real open passage")
		check(not mission.raycast(inside,base+Vector3(0,1.5,-house.size.y/2-2),[]).is_empty(),"house back wall has solid collision")
		var actor=mission.actors[3]
		actor.position=mission.field.ground(mission.field.sites[1].position+Vector3(0,0,25),0.15)
		actor.health=100
	elif frame==190:
		var actor=mission.actors[3]
		mission._spawn_bullet(actor.position+Vector3(0,1.1,6),Vector3(0,0,-780),p,true)
	elif frame==192:
		check(mission.actors[3].health<100,"swept ballistic projectile damages a soldier")
		p.equip_profile(27)
		sim.tick_weapon(10)
		var before=mission.bullets.size()
		if sim.fire(): mission.player_shot()
		check(mission.bullets.size()==before+8,"shotgun emits eight pellets for one trigger")
		mission.bullets.clear()
		var jeep=mission.vehicles[0]
		var hull=jeep.health
		mission._explode(jeep.position+Vector3(3,1,0),6,160,p)
		check(jeep.health<hull,"explosive blast damages an exposed vehicle hull")
		p.equip_slot(0)
	elif frame==210:
		mission.teleport_player(Vector3(10429,0,-13768))
		check(mission.field.chunks.size()<=9,"far travel unloads old detail tiles")
		check(mission.field.chunks.has(mission.field.chunk_key(p.position)),"far destination has a loaded collision tile")
	elif frame==240:
		check(p.is_on_floor(),"far terrain collision remains valid after streaming")
		mission.teleport_player(mission.field.spawn_position)
	elif frame==250:
		var jeep=mission.vehicles[0]
		check(jeep.board(p),"player enters the four-seat transport")
		for i in range(3):
			mission.actors[i].position=mission.field.ground(jeep.position+Vector3(i*2-2,0,3),0.15)
			mission.actors[i].set_physics_process(true)
		mission.order("BOARD")
		check(jeep.reservations.size()==3,"board command reserves three distinct passenger seats")
	elif frame==270:
		var jeep=mission.vehicles[0]
		var all_aboard=true
		for i in range(3): all_aboard=all_aboard and mission.actors[i].vehicle==jeep
		check(all_aboard,"AI squad members actually board their assigned seats")
		check(jeep.cab_frame.visible,"cab view retains the slim windshield frame")
		jeep_start=jeep.position
		var view_event=InputEventKey.new(); view_event.keycode=KEY_V; view_event.pressed=true
		p._unhandled_input(view_event)
		check(p.vehicle_external,"V selects external vehicle camera")
		Input.action_press("forward")
	elif frame==345:
		Input.action_release("forward")
		check(mission.vehicles[0].cab_frame.visible,"external view retains the complete windshield frame")
		check(p.camera.global_position.distance_to(p.global_position)>6,"external view places the camera behind the vehicle")
		check(absf(mission.vehicles[0].wheels[0].roll.rotation.x)>0.2,"wheels actually rotate while driving")
		var view_event=InputEventKey.new(); view_event.keycode=KEY_V; view_event.pressed=true
		p._unhandled_input(view_event)
		check(not p.vehicle_external,"V restores the cab camera")
		check(mission.vehicles[0].position.distance_to(jeep_start)>2,"transport moves under player throttle")
	elif frame==420:
		check(absf(mission.vehicles[0].speed)<1,"transport brakes to rest")
		mission.order("DISEMBARK")
		mission.vehicles[0].exit_actor(p)
		check(not is_instance_valid(p.vehicle) and p.collision_layer==2,"driver dismount restores on-foot collision")
		check(Vector2(p.position.x,p.position.z).distance_to(Vector2(mission.vehicles[0].position.x,mission.vehicles[0].position.z))<6,"dismount stays next to transport beyond old valley bounds")
		var dismounted=true
		for i in range(3):
			dismounted=dismounted and not is_instance_valid(mission.actors[i].vehicle)
			mission.actors[i].set_physics_process(false)
		check(dismounted,"squad dismount command restores all three soldiers")
		var hmg=mission.vehicles[6]
		mission.teleport_player(hmg.position+Vector3(0,0,3))
		check(hmg.board(p) and p.weapon.name=="M2HB","fixed emplacement equips its mounted weapon")
	elif frame==430:
		mission.vehicles[6].exit_actor(p)
		check(p.weapon.id==p.loadout[p.active_slot],"leaving emplacement restores the carried weapon")
		var heli=mission.vehicles[2]
		mission.teleport_player(heli.position+Vector3(4,0,0))
		check(heli.board(p),"player enters the transport helicopter")
		Input.action_press("jump")
	elif frame==550:
		Input.action_release("jump")
		var heli=mission.vehicles[2]
		check(heli.position.y-mission.field.height_at(heli.position.x,heli.position.z)>6,"helicopter ascends under collective input")
		check(not heli.exit_actor(p),"airborne dismount is blocked")
		Input.action_press("crouch")
	elif frame==890:
		Input.action_release("crouch")
		check(mission.vehicles[2].exit_actor(p),"helicopter lands and permits dismount")
		mission.teleport_player(mission.objectives[0].position)
		Input.action_press("interact")
	elif frame==1010:
		check(mission.objective_index==1,"village intelligence advances the mission")
		mission.teleport_player(mission.objectives[1].position)
	elif frame==1170:
		check(mission.objective_index==2,"relay sabotage advances the mission")
		mission.teleport_player(mission.objectives[2].position)
	elif frame==1290:
		check(mission.objective_index==3,"airfield transmission unlocks extraction")
		Input.action_release("interact")
		mission.teleport_player(mission.objectives[3].position)
	elif frame==1490:
		check(mission.state=="SUCCESS","all four stages complete through real interaction and extraction")
		check(mission.field.chunks.size()<=9,"detail tile count stays bounded through the whole operation")
		check(mission.field.middle_chunks.size()<=9,"middle tile count stays bounded through the whole operation")
		check(mission.field.vegetation.built_patches>0,"nearby streamed patches actually contain vegetation")
		# Route actual input event classes through the HUD, not just the zoom helper.
		mission.map_open=true
		var hud=mission.hud
		hud.map_zoom=false
		var pan=InputEventPanGesture.new(); pan.position=Vector2(770,440)*hud.view_scale; pan.delta=Vector2(0,-1)
		var old_span=hud.map_span(); hud._input(pan)
		check(hud.map_span()<old_span and hud.map_span()>1024,"trackpad scroll zooms continuously, without jumping to local view")
		var magnify=InputEventMagnifyGesture.new(); magnify.position=pan.position; magnify.factor=1.25
		old_span=hud.map_span(); hud._input(magnify)
		check(absf(hud.map_span()-old_span/1.25)<0.1,"trackpad pinch uses its scale factor")
		hud.map_zoom=true
		var pointer=Vector2(850,450)
		var anchor=(pointer-Vector2(440,110))/660
		var before=hud.map_origin()+anchor*hud.map_span()
		hud.zoom_map(0.8,pointer)
		check(before.distance_to(hud.map_origin()+anchor*hud.map_span())<0.01,"map zoom preserves geography under pointer")
		hud.zoom_map(0.000001,pointer); check(hud.map_span()==256,"map minimum zoom is bounded")
		hud.zoom_map(1000000,pointer); check(hud.map_span()==mission.field.LIMIT*2,"map maximum zoom is bounded")
		mission.map_open=false
		mission.state="ACTIVE"; mission.extract_progress=0
		mission.teleport_player(mission.field.spawn_position)
		ramp=StaticBody3D.new(); mission.add_child(ramp)
		ramp.position=mission.field.ground(mission.field.spawn_position+Vector3(45,0,20),3)
		ramp.rotation=Vector3(0.17,0,0.12)
		var shape=CollisionShape3D.new(); var bounds=BoxShape3D.new(); bounds.size=Vector3(12,1,16); shape.shape=bounds; ramp.add_child(shape)
		var jeep=mission.vehicles[0]; jeep.position=ramp.position+Vector3.UP*4
		jeep.rotation=Vector3.ZERO; jeep.tilt_velocity=Vector2.ZERO; jeep.velocity=Vector3.ZERO; jeep.speed=0
		drop_height=jeep.position.y
		var heli=mission.vehicles[2]
		heli.position=mission.field.ground(mission.field.spawn_position+Vector3(-45,0,-55),8)
		heli.velocity=Vector3.ZERO
		heli_drop_height=heli.position.y
	elif frame==1510:
		check(mission.vehicles[0].position.y<drop_height-0.35,"unsupported vehicle falls under gravity")
		check(mission.vehicles[2].position.y<heli_drop_height-0.35,"unoccupied helicopter falls under gravity")
	elif frame==1670:
		var jeep=mission.vehicles[0]
		check(jeep.suspension_contacts==4,"four tires acquire actual ramp collision contacts")
		check(absf(jeep.velocity.y)<0.8,"spring damping settles the dropped vehicle")
		check(jeep.global_basis.y.dot(ramp.global_basis.y)>0.995 and absf(jeep.rotation.x)>0.1 and absf(jeep.rotation.z)>0.06,"physical chassis follows both pitch and bank of ramp")
		var heli=mission.vehicles[2]
		check(absf(heli.position.y-mission.field.height_at(heli.position.x,heli.position.z))<0.5 and absf(heli.velocity.y)<0.5,"unoccupied helicopter lands on terrain collision")
		heli.position=mission.field.ground(mission.field.sites[1].position,20)
		heli.velocity=Vector3.ZERO
		heli.health=0
		heli_drop_height=heli.position.y
	elif frame==1700:
		var heli=mission.vehicles[2]
		check(heli.position.y<heli_drop_height-1,"disabled distant helicopter continues falling under gravity")
		check(heli.position.y>mission.field.height_at(heli.position.x,heli.position.z)+10,"airborne distant helicopter is not teleported into parked state")
		if not failed:
			print("INTEGRATION_PASS: ",checks," checks")
			mission.audio.silence()
			mission.get_tree().quit()
