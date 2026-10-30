extends RefCounted
## Original goal/state coordinator. RUNNING tasks retain their state across ticks.
## Design references and scope: docs/command-design.md (no third-party code copied).
var mission: Node3D
var enabled=true
var auto_follow=true
var mode="FOLLOW"
var goal: Dictionary={}
var status="Following the leader"
var outcome="IDLE"
var serial=0
var elapsed=0.0
var step_elapsed=0.0
var accumulator=0.0
var previous_transport: Node3D
var follow_exit: Node3D
var progress_position=Vector3.ZERO
var progress_age=0.0
var hint="Q: Move and cover"

func team() -> Array:
	return mission.actors.filter(func(a): return a.friendly and a.health>0)

func announce(value: String) -> void:
	if status==value: return
	status=value; mission.radio(value)

func phase(value: String,message: String) -> void:
	goal.phase=value; step_elapsed=0; progress_age=0
	if is_instance_valid(goal.get("source")): progress_position=goal.source.position
	announce(message)

func cancel() -> void:
	var source=goal.get("source")
	if is_instance_valid(source):
		source.logistics.drive_order=false; source.logistics.route.clear()
		source.logistics.awaiting_ramp=false; source.logistics.loading_aircraft=null; source.logistics.reverse_route=false
		for actor in team():
			if actor.boarding_target==source:
				source.reservations.erase(actor.boarding_seat); actor.boarding_target=null; actor.command="FOLLOW"
	goal={}; outcome="CANCELLED"; elapsed=0

func start(kind: String,source: Node3D=null,target: Node3D=null,point: Vector3=Vector3.ZERO) -> void:
	cancel(); serial+=1; outcome="RUNNING"; mode=kind
	goal={"kind":kind,"phase":"START","source":source,"target":target,"point":point,"members":[]}
	elapsed=0; step_elapsed=0; progress_age=0

func done(message: String,after: String="HOLD") -> void:
	goal={}; mode=after; outcome="SUCCESS"; announce(message)

func blocked(message: String) -> void:
	cancel(); mode="HOLD"; outcome="BLOCKED"; announce(message)

func hold() -> void:
	cancel(); mode="HOLD"
	for actor in team():
		if is_instance_valid(actor.vehicle): actor.vehicle.logistics.drive_order=false; actor.vehicle.logistics.route.clear()
		else: actor.command="HOLD"; actor.command_target=actor.position
	announce("Squad holding position")

func regroup() -> void:
	cancel(); mode="FOLLOW"; follow_exit=null
	for actor in team():
		if not is_instance_valid(actor.vehicle): actor.command="FOLLOW"; actor.plan_timer=0
		elif not is_instance_valid(mission.player.vehicle):
			actor.vehicle.logistics.drive_order=false
			if not actor.vehicle.exit_actor(actor): follow_exit=actor.vehicle
	if is_instance_valid(mission.player.vehicle): mission.board_squad(mission.player.vehicle)
	announce("Following the leader")

func source_for_trip(point: Vector3) -> Node3D:
	var current=mission.player.vehicle
	if is_instance_valid(current) and current.logistics.ground_vehicle(): return current
	if is_instance_valid(mission.selected_vehicle) and mission.selected_vehicle.logistics.ground_vehicle() and not mission.selected_vehicle.logistics.secured: return mission.selected_vehicle
	for actor in team():
		if is_instance_valid(actor.vehicle) and actor.vehicle_seat==0 and actor.vehicle.logistics.ground_vehicle() and not actor.vehicle.logistics.secured: return actor.vehicle
	if mission.player.position.distance_to(point)<150: return null
	return mission.command_source()

func go(point: Vector3,attack: Node3D=null) -> void:
	mission.command_point=point; mission.command_marker_time=12
	var source=source_for_trip(point) if not is_instance_valid(attack) else null
	start("ATTACK" if is_instance_valid(attack) else "GO",source,attack,point)

func board(source: Node3D) -> void:
	start("BOARD",source)

func dismount(source: Node3D) -> void:
	start("DISMOUNT",source)

func load_transport(target: Node3D) -> void:
	var source=mission.command_source(target)
	if not is_instance_valid(source):
		if not target.logistics.cargo.is_empty(): unload_transport(target)
		else: blocked("No available ground vehicle to load")
		return
	start("LOAD",source,target)

func unload_transport(target: Node3D) -> void:
	if target.logistics.cargo.is_empty(): dismount(target); return
	start("UNLOAD",target.logistics.cargo[0],target)

func suggested(context: Dictionary) -> String:
	var target=context.get("vehicle")
	if is_instance_valid(target):
		if target.kind=="CARGO": return "Q: Load transport automatically" if is_instance_valid(mission.command_source(target)) else "Q: Unload and regroup"
		return "Q: Dismount and regroup" if team().any(func(a): return a.vehicle==target) and mission.player.vehicle!=target else "Q: Crew this vehicle"
	var actor=context.get("collider")
	if is_instance_valid(actor) and actor in mission.actors and not actor.friendly: return "Q: Engage this target"
	return "Q: Move and cover" if context.has("position") else "Q: Regroup"

func smart(context: Dictionary) -> void:
	var target=context.get("vehicle")
	if is_instance_valid(target):
		if target.kind=="CARGO": load_transport(target)
		elif team().any(func(a): return a.vehicle==target) and mission.player.vehicle!=target: dismount(target)
		else: board(target)
		return
	var hit=context.get("collider")
	if is_instance_valid(hit) and hit in mission.actors and not hit.friendly: go(hit.position,hit)
	elif context.has("position"): go(context.position)
	else: regroup()

func enroll(source: Node3D,require_driver: bool) -> bool:
	if require_driver and not mission.ensure_driver(source): blocked("No available squad driver"); return false
	mission.board_squad(source)
	goal.members=team().filter(func(a): return a.vehicle==source or a.boarding_target==source)
	if goal.members.is_empty(): blocked("No free seats or available teammates"); return false
	return true

func members_aboard() -> bool:
	var members: Array=goal.members
	return not members.is_empty() and members.all(func(a): return a.health<=0 or a.vehicle==goal.source)

func order_feet(command: String,point: Vector3) -> void:
	for actor in team():
		if is_instance_valid(actor.vehicle): continue
		if is_instance_valid(actor.boarding_target): actor.boarding_target.reservations.erase(actor.boarding_seat); actor.boarding_target=null
		actor.command=command; actor.command_target=point+Vector3((actor.mind_id%3-1)*2,0,2)
		actor.priority_target=goal.get("target"); actor.plan_timer=0

func feet_ready() -> bool:
	return team().all(func(a): return not is_instance_valid(a.vehicle))

func tick(dt: float) -> void:
	if not enabled: return
	accumulator+=dt
	if accumulator<0.1: return
	var step=accumulator; accumulator=0
	hint=suggested(mission.aim_context())
	if goal.is_empty():
		if auto_follow: follow_tick()
		return
	elapsed+=step; step_elapsed+=step
	var source=goal.get("source")
	if is_instance_valid(source) and source.health<=0: blocked("Command stopped: vehicle disabled"); return
	if elapsed>180: blocked("Command stopped: task timed out"); return
	match goal.kind:
		"BOARD","GO","ATTACK": trip_tick(source)
		"LOAD": load_tick(source)
		"UNLOAD": unload_tick(source)
		"DISMOUNT":
			if goal.phase=="START": mission.dismount_squad(source); phase("EXITING","Stopping and dismounting")
			if team().all(func(a): return a.vehicle!=source or a.vehicle_seat==-2): done("Squad dismounted")
	if goal.is_empty(): return
	if is_instance_valid(source) and goal.phase in ["DRIVING","LOADING","UNLOADING"]:
		if source.position.distance_to(progress_position)>0.75: progress_position=source.position; progress_age=0
		else: progress_age+=step
		if progress_age>15: blocked("Command blocked: route or ramp obstructed")

func trip_tick(source: Node3D) -> void:
	if goal.phase=="START":
		if is_instance_valid(source):
			if not enroll(source,goal.kind!="BOARD"): return
			phase("BOARDING","Squad boarding automatically")
		else:
			for actor in team():
				if is_instance_valid(actor.vehicle):
					var plane=actor.vehicle if actor.vehicle.kind=="CARGO" else actor.vehicle.containing_transport()
					if is_instance_valid(plane) and not plane.supported_and_stopped(): blocked("Transport must land and stop first"); return
			phase("ON_FOOT","Dismounting for the move")
	if goal.phase=="BOARDING" and members_aboard():
		if goal.kind=="BOARD": done("Vehicle ready; choose a destination", "READY"); return
		source.set_destination(goal.point); phase("DRIVING","Driver en route")
	elif goal.phase=="DRIVING" and not source.logistics.drive_order and absf(source.speed)<1:
		if mission.player.vehicle==source: done("Destination reached","FOLLOW"); return
		mission.dismount_squad(source); phase("ON_FOOT","Arrived; dismounting and covering")
	if goal.phase=="ON_FOOT":
		for actor in team():
			if not is_instance_valid(actor.vehicle): continue
			var transport=actor.vehicle
			transport.logistics.drive_order=false
			if transport.kind=="CARGO" and transport.supported_and_stopped() and not transport.logistics.doors_open: transport.logistics.toggle_doors()
			transport.exit_actor(actor)
	if goal.phase=="ON_FOOT" and feet_ready():
		order_feet("ATTACK" if goal.kind=="ATTACK" else "MOVE",goal.point)
		phase("WALKING","Squad advancing and covering")
	if goal.phase=="WALKING":
		if goal.kind=="ATTACK":
			if is_instance_valid(goal.target) and goal.target.health<=0: done("Target neutralized")
		elif team().all(func(a): return a.position.distance_to(goal.point)<9): done("Position secured")

func load_tick(source: Node3D) -> void:
	var plane=goal.target
	if not is_instance_valid(plane) or plane.health<=0: blocked("Transport unavailable"); return
	if goal.phase=="START":
		if not plane.supported_and_stopped(): blocked("Transport must land and stop first"); return
		if not enroll(source,true): return
		phase("BOARDING","Assigning crew for loading")
	if goal.phase=="BOARDING" and members_aboard():
		if not source.logistics.request_loading(plane): blocked("Cargo bay full or vehicle not loadable"); return
		phase("LOADING","Driver approaching and loading automatically")
	if goal.phase=="LOADING" and source.logistics.secured: phase("CLOSING","Cargo secured; closing ramp")
	if goal.phase=="CLOSING":
		if not plane.logistics.doors_open or plane.logistics.toggle_doors(): done("Transport ready: cargo secured and ramp closed")

func unload_tick(source: Node3D) -> void:
	var plane=goal.target
	if not is_instance_valid(plane): blocked("Transport unavailable"); return
	if goal.phase=="START":
		if not plane.supported_and_stopped(): blocked("Transport must land and stop first"); return
		if not mission.ensure_driver(source): blocked("No available squad driver"); return
		phase("DRIVER","Preparing to unload")
	if goal.phase=="DRIVER" and is_instance_valid(source.occupants[0]):
		if not source.logistics.request_unloading(): blocked("Unload ramp obstructed"); return
		phase("UNLOADING","Driver reversing down the ramp")
	if goal.phase=="UNLOADING" and not source.logistics.drive_order and absf(source.speed)<1:
		source.logistics.reverse_route=false; mission.dismount_squad(source)
		phase("EXITING","Cargo unloaded; crew dismounting")
	if goal.phase=="EXITING" and team().all(func(a): return a.vehicle!=source):
		for actor in team():
			if not is_instance_valid(actor.vehicle): actor.command="HOLD"; actor.command_target=actor.position
		if plane.logistics.doors_open and not plane.logistics.toggle_doors(): return
		done("Unloaded; squad covering the area")

func follow_tick() -> void:
	var current=mission.player.vehicle
	if current!=previous_transport:
		var previous=previous_transport; previous_transport=current
		if mode in ["FOLLOW","READY"]:
			if is_instance_valid(current):
				mission.board_squad(current); mode="FOLLOW"; announce("Squad following you into the vehicle")
			elif is_instance_valid(previous):
				mission.dismount_squad(previous); follow_exit=previous; announce("Squad following you out of the vehicle")
	if mode=="FOLLOW" and is_instance_valid(follow_exit):
		if follow_exit.kind=="CARGO" and follow_exit.supported_and_stopped() and not follow_exit.logistics.doors_open: follow_exit.logistics.toggle_doors()
		var remaining=team().filter(func(a): return a.vehicle==follow_exit)
		for actor in remaining: follow_exit.exit_actor(actor)
		if remaining.is_empty(): follow_exit=null; announce("Following the leader")
