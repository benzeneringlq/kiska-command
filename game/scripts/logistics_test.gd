extends RefCounted
## Actual-engine end-to-end logistics: orders, moving interiors, loading and airdrop.
var mission: Node3D
var checks=0
var failed=false
var stage=0
var clock=0
var jeep: Node3D
var truck: Node3D
var tank: Node3D
var plane: Node3D
var origin=Vector3.ZERO
var local_start=Vector3.ZERO
var saved_rounds=0

func check(condition: bool,label: String) -> void:
	if not condition:
		failed=true; push_error("LOGISTICS_FAILED: "+label); mission.get_tree().quit(3)
	else: checks+=1; print("LOGISTICS_CHECK: ",label)

func next() -> void:
	stage+=1; clock=0
	print("LOGISTICS_STAGE: ",stage)

func tick(_frame: int) -> void:
	if failed: return
	clock+=1
	var p=mission.player
	if stage==0 and clock==20:
		jeep=mission.vehicles[0]; truck=mission.vehicles[9]; tank=mission.vehicles[10]; plane=mission.vehicles[11]
		mission.selected_vehicle=jeep
		mission.seat_menu=jeep; mission.choose_seat(1)
		check(p.vehicle==jeep and p.vehicle_seat==1,"player chooses a passenger seat through the actual menu handler")
		for i in range(3):
			var actor=mission.actors[i]; actor.position=mission.field.ground(jeep.position+Vector3(-3+i*3,0,3),0.15); actor.set_physics_process(true)
		mission.order("BOARD")
		check(mission.actors[0].boarding_seat==0,"first squadmate reserves the driver seat before passenger seats")
		next()
	elif stage==1 and clock==100:
		check(jeep.occupants[0]==mission.actors[0],"squadmate actually reaches and boards the driver seat")
		origin=jeep.position
		mission.order_at("MOVE",jeep.position-Vector3(0,0,30))
		next()
	elif stage==2 and clock==200:
		check(jeep.position.distance_to(origin)>8,"AI driver moves vehicle toward the commanded destination")
		check(p.position.distance_to(jeep.seat_position(1))<0.5,"fixed-seat passenger stays in the selected seat")
		check(jeep.can_shoot(1) and not jeep.can_shoot(0),"passenger can fire while driver operates the vehicle")
		saved_rounds=mission.sim.weapon_state().rounds; mission.sim.tick_weapon(10); Input.action_press("fire")
		next()
	elif stage==3 and clock==10:
		Input.action_release("fire")
		check(mission.sim.weapon_state().rounds<saved_rounds,"passenger actually fires a carried weapon")
		mission.order_at("HOLD",jeep.position)
		next()
	elif stage==4 and clock==100:
		check(absf(jeep.speed)<0.8,"AI driver stops on hold command")
		mission.order("DISEMBARK"); jeep.exit_actor(p)
		mission.selected_vehicle=tank
		for i in range(3):
			var actor=mission.actors[i]; actor.position=mission.field.ground(tank.position+Vector3(i*2-2,0,3),0.15); actor.set_physics_process(true)
		check(plane.logistics.toggle_doors(),"transport rear door opens and enables loading ramp")
		mission.order("BOARD")
		next()
	elif stage==5 and clock==100:
		check(tank.occupants[0]==mission.actors[0],"squadmate boards the tank as driver")
		mission.order("LOAD")
		check(tank.logistics.drive_order and tank.logistics.route.size()>0,"load order sends AI driver toward the actual ramp")
		next()
	elif stage==6:
		if clock%120==0: print("LOAD_PROGRESS: p=",plane.to_local(tank.position)," speed=",tank.speed," route=",tank.logistics.route.size()," contacts=",tank.suspension_contacts)
		if tank.logistics.secured:
			check(plane.logistics.inside(tank),"AI drives tank physically through the ramp and fully into the bay")
			check(is_instance_valid(tank.occupants[0]),"occupied tank can be restrained without ejecting its driver")
			var actor=tank.occupants[2]
			if is_instance_valid(actor): tank.exit_actor(actor); actor.set_physics_process(false); actor.position=plane.to_global(Vector3(-3,1.3,10))
			mission.teleport_player(tank.position+Vector3(3,0,0))
			mission.seat_menu=tank; mission.choose_seat(2)
			check(p.vehicle==tank,"player boards tank while it is cargo")
			check(tank.exit_actor(p),"player can dismount a tank inside the transport")
			check(p.vehicle==plane and p.vehicle_seat==-2 and plane.to_local(p.position).y>1,"tank dismount places the player in the aircraft interior")
			local_start=plane.to_local(p.position); Input.action_press("back")
			next()
		elif clock>2200: check(false,"AI loading timed out")
	elif stage==7 and clock==30:
		Input.action_release("back")
		check(plane.to_local(p.position).distance_to(local_start)>0.8,"player actually walks on the cargo floor")
		check(absf(plane.to_local(p.position).y-1.2)<0.4,"cargo floor prevents falling through the aircraft")
		mission.seat_menu=plane; mission.choose_seat(0)
		check(p.vehicle==plane and p.vehicle_seat==0,"player takes the transport pilot seat")
		check(plane.logistics.toggle_doors(),"door closes after tank is fully loaded")
		origin=plane.position; Input.action_press("forward"); Input.action_press("jump")
		next()
	elif stage==8 and clock==600:
		Input.action_release("forward"); Input.action_release("jump")
		check(plane.position.distance_to(origin)>100,"loaded transport flies under pilot input")
		check(plane.position.y-mission.field.height_at(plane.position.x,plane.position.z)>15,"transport takes off with tank aboard")
		var relative=plane.global_transform.affine_inverse()*tank.global_transform
		check(relative.origin.distance_to(tank.logistics.cargo_pose.origin)<0.05,"cargo restraints preserve the tank pose throughout flight")
		check(plane.logistics.walk_aboard(p),"pilot can enter the moving aircraft interior")
		mission.seat_menu=tank; mission.choose_seat(2)
		check(p.vehicle==tank and tank.exit_actor(p),"tank dismount is supported during flight")
		check(p.vehicle==plane and plane.to_local(p.position).y>1,"airborne tank dismount stays in the aircraft, not on island ground")
		local_start=plane.to_local(p.position); Input.action_press("back")
		next()
	elif stage==9 and clock==30:
		Input.action_release("back")
		check(plane.to_local(p.position).distance_to(local_start)>0.8,"player walks inside the aircraft while it is moving")
		check(absf(plane.to_local(p.position).y-1.2)<0.5,"moving aircraft floor supports the dismounted player")
		mission.seat_menu=plane; mission.choose_seat(0)
		check(plane.logistics.toggle_doors() and plane.logistics.airdrop(),"pilot opens door and releases cargo in flight")
		check(tank.logistics.parachute and not tank.logistics.secured and not is_instance_valid(tank.logistics.carrier),"airdrop removes restraints and deploys the slowing parachute")
		next()
	elif stage==10 and clock==80:
		print("DROP_STATE: separation=",tank.position.distance_to(plane.position)," velocity=",tank.velocity," chute=",tank.logistics.parachute," contacts=",tank.suspension_contacts)
		check(tank.position.distance_to(plane.position)>20,"dropped tank separates from the transport")
		check(tank.velocity.y>= -7.1,"cargo parachute limits descent speed")
		plane.exit_actor(p,true); plane.set_physics_process(false)
		truck.position=mission.field.ground(mission.field.spawn_position+Vector3(-35,0,-10),0.15)
		jeep.position=mission.field.ground(truck.position+Vector3(0,0,8),0.15); jeep.velocity=Vector3.ZERO; jeep.speed=0
		mission.teleport_player(truck.position+Vector3(4,0,0))
		check(truck.logistics.attach_tow(jeep),"ground vehicle accepts a tow connection")
		check(not jeep.logistics.attach_tow(truck),"tow cycles are rejected")
		check(truck.board(p,0),"player takes the truck driver seat")
		origin=jeep.position; Input.action_press("forward")
		next()
	elif stage==11 and clock==100:
		Input.action_release("forward")
		check(jeep.position.distance_to(origin)>3,"tow constraint actually pulls the second vehicle")
		check(jeep.position.distance_to(truck.position)<15,"tow cable maintains bounded separation")
		truck.logistics.detach_tow()
		check(not is_instance_valid(jeep.logistics.tow_parent),"tow connection releases cleanly")
		truck.speed=0; truck.velocity=Vector3.ZERO
		mission.seat_menu=truck; mission.choose_seat(-2)
		check(p.vehicle==truck and p.vehicle_seat==-2,"truck offers a walkable bed instead of a fixed seat")
		local_start=truck.to_local(p.position); Input.action_press("forward")
		next()
	elif stage==12 and clock==30:
		Input.action_release("forward")
		check(truck.to_local(p.position).distance_to(local_start)>0.8,"player actually moves inside the truck bed")
		check(absf(truck.to_local(p.position).y-1.15)<0.4,"truck bed has a solid walkable floor")
		var driver=mission.actors[1]
		tank.exit_actor(driver,true); driver.set_physics_process(true)
		check(truck.board(driver,0),"squadmate takes the wheel while player walks in truck bed")
		mission.selected_vehicle=truck; mission.order_at("MOVE",truck.position-Vector3(0,0,25))
		origin=truck.position; local_start=truck.to_local(p.position)
		next()
	elif stage==13 and clock==180:
		check(truck.position.distance_to(origin)>6,"AI drives the truck with a walking passenger aboard")
		check(truck.to_local(p.position).distance_to(local_start)<0.6,"walking passenger is carried with the moving truck")
		truck.logistics.drive_order=false
		plane.global_transform=Transform3D(Basis.IDENTITY,mission.field.ground(mission.field.spawn_position+Vector3(0,0,120),0.1))
		plane.speed=0; plane.velocity=Vector3.ZERO
		jeep.global_transform=plane.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.35,6))
		jeep.velocity=Vector3.ZERO; jeep.speed=0
		plane.logistics.tick()
		check(jeep.logistics.secured,"unoccupied vehicle inside cargo bay locks automatically")
		check(plane.logistics.toggle_secure(),"manual restraints release an automatically secured vehicle")
		plane.logistics.tick()
		check(not jeep.logistics.secured,"manual release stays unlocked until explicitly secured again")
		check(plane.logistics.toggle_secure() and jeep.logistics.secured,"unoccupied cargo can be manually fixed again")
		truck.exit_actor(p,true)
		mission.teleport_player(mission.field.sites[1].position)
		origin=truck.position; truck.set_destination(truck.position-Vector3(0,0,20))
		next()
	elif stage==14 and clock==180:
		check(truck.position.distance_to(origin)>5,"AI ground driver continues beyond the player collision streaming range")
		check(absf(truck.position.y-mission.field.height_at(truck.position.x,truck.position.z))<0.5,"distant AI vehicle stays on offline terrain instead of falling through unloaded tiles")
		var trailer=mission.vehicles[1]
		truck.speed=0
		trailer.position=mission.field.ground(truck.position+truck.global_basis.z*8,0.12)
		trailer.velocity=Vector3.ZERO; trailer.speed=0
		check(truck.logistics.attach_tow(trailer),"distant driver can connect a ground trailer")
		origin=trailer.position; truck.set_destination(truck.position-truck.global_basis.z*20)
		next()
	elif stage==15 and clock==150:
		var trailer=mission.vehicles[1]
		check(trailer.position.distance_to(origin)>3 and trailer.position.distance_to(truck.position)<13,"AI tow convoy continues moving outside collision streaming range")
		print("LOGISTICS_PASS: ",checks," checks")
		mission.audio.silence(); mission.get_tree().quit()
