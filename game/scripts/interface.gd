extends Control
## Resolution-independent field interface, rendered with vector primitives.
var mission: Node3D
var font: Font
var show_performance = true
const INK = Color(0.87,0.91,0.84)
const DIM = Color(0.53,0.62,0.56)
const GOLD = Color(0.93,0.72,0.37)
const MINT = Color(0.42,0.81,0.71)
const PANEL = Color(0.035,0.065,0.062,0.91)
var view_scale = Vector2.ONE
var map_width=49152.0
var map_centre=Vector2.ZERO
var map_dragging=false
var map_zoom: bool:
	get: return map_width<8192.0
	set(value):
		map_width=1024.0 if value else mission.field.LIMIT*2
		map_centre=Vector2(mission.player.position.x,mission.player.position.z) if value else Vector2.ZERO
		_clamp_map()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face = FontVariation.new()
	face.base_font = load("res://fonts/NotoSansSC.ttf")
	face.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):550.0}
	font = face

func _process(_dt: float) -> void:
	queue_redraw()

func text_at(p: Vector2, value: String, font_size = 16, color = INK, max_width = -1.0) -> void:
	var display = tr(value)
	if Settings.language == "zh_CN" and font_size<=24: font_size += 2
	var available = max_width if max_width>0 else 1416.0-p.x
	var width = font.get_string_size(display,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var fitted = font_size if width<=available else maxi(10,int(font_size*available/width))
	draw_string(font,p,display,HORIZONTAL_ALIGNMENT_LEFT,available,fitted,color)

func line(a: Vector2,b: Vector2,color = DIM,width = 1.0) -> void:
	draw_line(a,b,color,width,true)

func panel(rect: Rect2) -> void:
	draw_rect(rect,PANEL)
	draw_rect(rect,Color(0.40,0.51,0.43,0.32),false,1)

func bar(rect: Rect2, value: float, color: Color) -> void:
	draw_rect(rect,Color(0.21,0.28,0.24,0.7))
	draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(value,0,1),rect.size.y)),color)

func button(rect: Rect2, label: String, primary = false) -> void:
	var pointer = get_global_mouse_position()/view_scale
	var hover = rect.has_point(pointer)
	draw_rect(rect,Color(0.24,0.32,0.27) if hover else (GOLD if primary else Color(0.11,0.17,0.14)))
	draw_rect(rect,GOLD if primary else DIM,false,1)
	text_at(rect.position+Vector2(22,31),label,17,Color(0.08,0.12,0.1) if primary and not hover else INK,rect.size.x-40)

func _input(event: InputEvent) -> void:
	if mission.map_open:
		if event is InputEventPanGesture:
			zoom_map(exp(clampf(event.delta.y*0.10,-0.7,0.7)),event.position/view_scale)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMagnifyGesture:
			if event.factor>0: zoom_map(1.0/event.factor,event.position/view_scale)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var amount=maxf(event.factor,0.01)
			zoom_map(exp((-0.20 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.20)*amount),event.position/view_scale)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			map_dragging=event.pressed and _on_map(event.position/view_scale)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion and map_dragging:
			map_centre-=event.relative/view_scale/660*map_width
			_clamp_map()
			get_viewport().set_input_as_handled()
			return
	else: map_dragging=false
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position/view_scale
		if is_instance_valid(mission.seat_menu):
			var v=mission.seat_menu
			for i in range(v.seat_count):
				if Rect2(440,205+i*62,560,52).has_point(p): mission.choose_seat(i); break
			if v.kind in ["TRUCK","CARGO"] and Rect2(440,205+v.seat_count*62,560,52).has_point(p): mission.choose_seat(-2)
			get_viewport().set_input_as_handled(); return
		if mission.vehicle_menu:
			for i in range(mission.vehicles.size()):
				if Rect2(310,125+i*54,820,48).has_point(p):
					mission.selected_vehicle=mission.vehicles[i]; mission.vehicle_menu=false; mission._sync_mouse(); break
			get_viewport().set_input_as_handled(); return
		if mission.inventory_open:
			for slot in range(3):
				if Rect2(90+slot*420,125,400,64).has_point(p): mission.inventory_slot=slot
			var portable=mission.weapon_profiles.filter(func(w): return w.portable)
			for i in range(portable.size()):
				if Rect2(90+(i%6)*211,235+(i/6)*76,195,67).has_point(p): mission.player.assign_weapon(mission.inventory_slot,int(portable[i].id))
			get_viewport().set_input_as_handled()
			return
		if mission.command_open:
			for i in range(mission.command_options().size()):
				if Rect2(280+(i%3)*290,285+(i/3)*104,275,83).has_point(p): mission.select_command(i); break
			get_viewport().set_input_as_handled(); return
		if mission.state in ["BRIEFING","PAUSED","SUCCESS","FAILED"]:
			if Rect2(840,792,165,44).has_point(p):
				Settings.toggle_language()
				get_viewport().set_input_as_handled()
				return
			if Rect2(1015,792,165,44).has_point(p):
				Settings.toggle_fullscreen()
				get_viewport().set_input_as_handled()
				return
			if Rect2(1190,792,160,44).has_point(p):
				Settings.cycle_render_scale()
				get_viewport().set_input_as_handled()
				return
			if Rect2(90,710,350,52).has_point(p):
				if mission.state=="BRIEFING": mission.start()
				elif mission.state=="PAUSED":
					mission.state="ACTIVE"
					Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
				else: mission.get_tree().reload_current_scene()
				get_viewport().set_input_as_handled()
			elif Rect2(90,780,350,42).has_point(p): mission.get_tree().quit()
		elif mission.map_open:
			if Rect2(1140,110,230,44).has_point(p): map_zoom=not map_zoom
			# Click a location on the tactical map to issue a move order.
			var bounds = Rect2(440,110,660,660)
			if bounds.has_point(p):
				var map_p = map_origin()+(p-bounds.position)/bounds.size*map_span()
				var destination: Vector3 = mission.field.ground(Vector3(map_p.x,0,map_p.y))
				mission.order_at("MOVE",destination)
			get_viewport().set_input_as_handled()

func _draw() -> void:
	if not is_instance_valid(mission.player): return
	view_scale = size/Vector2(1440,900)
	draw_set_transform(Vector2.ZERO,0,view_scale)
	if mission.state in ["BRIEFING","PAUSED","SUCCESS","FAILED"]:
		_draw_menu()
		return
	if mission.map_open:
		_draw_map()
	elif mission.inventory_open:
		_draw_inventory()
	else:
		_draw_hud()
		if mission.command_open: _draw_commands()
		if is_instance_valid(mission.seat_menu): _draw_seats()
		if mission.vehicle_menu: _draw_vehicle_selection()

func _draw_menu() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.025,0.05,0.045,0.86))
	# Subtle plotting grid.
	for x in range(0,1441,60): line(Vector2(x,0),Vector2(x,900),Color(0.3,0.4,0.3,0.06))
	for y in range(0,901,60): line(Vector2(0,y),Vector2(1440,y),Color(0.3,0.4,0.3,0.06))
	line(Vector2(90,90),Vector2(1350,90),DIM)
	text_at(Vector2(90,70),"R / FIELD OPERATIONS",18,GOLD)
	text_at(Vector2(1090,70),"SINGLE PLAYER  /  01",16,DIM)
	text_at(Vector2(90,169),"SQUAD TACTICAL FPS",22,DIM)
	text_at(Vector2(84,242),"KISKA COMMAND",76,INK)
	var title = "DAWN CORRIDOR"
	var subtitle = "KISKA ISLAND / FICTIONAL OPERATION / 0540 HOURS"
	if mission.state=="PAUSED":
		title="MISSION PAUSED"
		subtitle="Take a breath. Your squad is holding position."
	elif mission.state=="SUCCESS":
		title="EXTRACTION COMPLETE"
		subtitle="The evacuation corridor is open. Mission accomplished."
	elif mission.state=="FAILED":
		title="OPERATOR DOWN"
		subtitle="The mission is over. Regroup and try another approach."
	text_at(Vector2(90,302),title,26,GOLD)
	text_at(Vector2(90,337),subtitle,15,DIM)
	line(Vector2(90,366),Vector2(710,366),Color(0.4,0.5,0.4,0.4))
	if mission.state in ["SUCCESS","FAILED"]:
		var survivors = 0
		for actor in mission.actors:
			if actor.friendly and actor.health>0: survivors+=1
		text_at(Vector2(90,420),"AFTER ACTION REPORT",16,DIM)
		text_at(Vector2(90,475),tr("%02d   HOSTILES NEUTRALIZED") % mission.kills,24)
		text_at(Vector2(90,525),tr("%d / 3   SQUAD SURVIVING") % survivors,24)
		text_at(Vector2(90,575),tr("%02d:%02d   ELAPSED") % [int(mission.elapsed)/60,int(mission.elapsed)%60],24)
	else:
		text_at(Vector2(90,402),"Kiska harbor: recover intelligence and open a coastal evacuation route.",15,DIM,620)
		text_at(Vector2(90,431),"Alpha must open a route north before the evacuation convoy arrives.",15,DIM,620)
		for i in range(mission.objectives.size()):
			text_at(Vector2(90,476+i*42),"%02d   %s" % [i+1,tr(mission.objectives[i].title)],17,INK)
		text_at(Vector2(90,650),"Real island relief / fictional camps / transport at harbor staging",14,MINT,620)
	text_at(Vector2(90,671),"LOW HEALTH. NO RESPAWNS. FRIENDLY FIRE ACTIVE.",14,GOLD)
	var label = "DEPLOY SQUAD     /     ENTER"
	if mission.state=="PAUSED": label="RESUME MISSION     /     ENTER"
	elif mission.state in ["SUCCESS","FAILED"]: label="RETRY MISSION     /     ENTER"
	button(Rect2(90,710,350,52),label,true)
	button(Rect2(90,780,350,42),"QUIT TO DESKTOP")
	panel(Rect2(840,157,510,608))
	text_at(Vector2(870,203),"FIELD MANUAL",20,GOLD)
	line(Vector2(870,225),Vector2(1320,225),DIM)
	var controls = [["W A S D","Move / drive"],["MOUSE / RMB","Look / aim down sights"],["LMB / R","Fire / reload"],["SHIFT / C / SPACE","Sprint / crouch / jump"],["1 / 2 / 3","Select carried weapon"],["B","Backpack / all weapons unlocked"],["Q","Squad orders / board / dismount"],["E","Enter vehicle / dismount"],["E (HOLD)","Interact with mission objective"],["M","Tactical map / click to order"],["SPACE / C","Helicopter: ascend / descend"],["F10 / F11","Language / fullscreen"]]
	for i in range(controls.size()):
		text_at(Vector2(870,266+i*36),controls[i][0],14,MINT,170)
		text_at(Vector2(1052,266+i*36),controls[i][1],14,INK,268)
	text_at(Vector2(870,720),"Move deliberately. Use cover. Keep the team close.",14,DIM)
	text_at(Vector2(840,778),"F10 LANGUAGE    F11 FULLSCREEN    3D SCALE AFFECTS PERFORMANCE",12,DIM,510)
	button(Rect2(840,792,165,44),"Language: English")
	button(Rect2(1015,792,165,44),"Fullscreen: On" if Settings.fullscreen else "Fullscreen: Off")
	button(Rect2(1190,792,160,44),tr("3D: %d%%") % roundi(Settings.render_scale*100))
	text_at(Vector2(90,865),"OPEN-SOURCE TACTICAL FPS  /  GODOT + C++",13,DIM)
	text_at(Vector2(1125,865),"PROTOTYPE   v0.3",13,GOLD)

func _draw_hud() -> void:
	var p: CharacterBody3D = mission.player
	var scoped=p.aiming and p.weapon.optic=="scope"
	if scoped: _draw_scope()
	# Thin letterbox edges tie the screen together without hiding the world.
	draw_rect(Rect2(0,0,1440,6),Color(0.03,0.06,0.05,0.8))
	_draw_compass()
	panel(Rect2(34,32,310,90))
	text_at(Vector2(52,57),"KISKA COMMAND   /   ALPHA 1",14,DIM)
	text_at(Vector2(52,86),mission.phase,22,GOLD)
	var distance: int = int(p.position.distance_to(mission.objective_position()))
	text_at(Vector2(52,109),tr("%03d m  /  OBJECTIVE %d OF 4") % [distance,mission.objective_index+1],13,INK,270)
	if show_performance:
		panel(Rect2(1142,24,265,75))
		text_at(Vector2(1160,45),"%d FPS   /   %.1f ms" % [Engine.get_frames_per_second(),Performance.get_monitor(Performance.TIME_PROCESS)*1000],14,MINT)
		text_at(Vector2(1160,66),tr("DETAIL TILES %d / 9") % mission.field.chunks.size(),12,DIM)
		text_at(Vector2(1160,85),"KISKA / USGS 3DEP",12,DIM)
	if not p.aiming: _draw_markers()
	var c = Vector2(720,450)
	if p.sprinting: pass
	elif p.aiming:
		if not scoped:
			draw_circle(c,2.8,Color(0.04,0.05,0.04,0.6))
			draw_circle(c,1.5,Color(1.0,0.2,0.1) if p.weapon.optic=="reflex" else INK)
	else:
		var gap = 7.0+Vector2(p.velocity.x,p.velocity.z).length()*1.5+p.kick*90
		for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			line(c+direction*gap,c+direction*(gap+5),Color(0.87,0.91,0.84,0.72))
	if mission.hit_flash>0:
		for dx in [-1,1]:
			for dy in [-1,1]: line(c+Vector2(dx*10,dy*10),c+Vector2(dx*16,dy*16),Color(0.94,0.74,0.4,mission.hit_flash),2)
	# Squad column.
	panel(Rect2(34,657,267,197))
	text_at(Vector2(52,684),"ALPHA ELEMENT",14,DIM)
	for i in range(3):
		var actor: CharacterBody3D = mission.actors[i]
		var y = 716+i*45
		draw_circle(Vector2(57,y-5),3.5,MINT if actor.health>0 else Color(0.8,0.3,0.22))
		text_at(Vector2(70,y),actor.call_sign,15,INK if actor.health>0 else DIM)
		text_at(Vector2(182,y),actor.status if actor.health>0 else "KIA",12,MINT if actor.health>0 else GOLD)
		bar(Rect2(70,y+7,191,3),actor.health/100.0,MINT)
	panel(Rect2(1131,715,275,139))
	var weapon: Dictionary = mission.sim.weapon_state()
	text_at(Vector2(1151,744),p.weapon.name,16,DIM,230)
	text_at(Vector2(1150,791),"%02d" % weapon.rounds,44,INK)
	text_at(Vector2(1222,787),"/ %03d" % weapon.reserve,22,DIM)
	text_at(Vector2(1152,826),"RELOADING" if weapon.reload>0 else ("AUTO" if p.weapon.automatic else "SEMI"),13,GOLD)
	text_at(Vector2(1280,826),"R  RELOAD",12,DIM)
	if weapon.reload>0: bar(Rect2(1151,839,233,3),1-weapon.reload/weapon.reload_duration,GOLD)
	# Vital status sits above commands, so the weapon remains readable.
	panel(Rect2(339,765,163,90))
	panel(Rect2(507,804,513,64))
	text_at(Vector2(355,791),"OPERATOR",12,DIM)
	text_at(Vector2(355,821),"%03d" % p.health,26,INK if p.health>35 else GOLD)
	bar(Rect2(355,835,130,4),p.health/100,MINT if p.health>35 else GOLD)
	bar(Rect2(355,845,130,2),p.stamina,DIM)
	for slot in range(3):
		text_at(Vector2(520+slot*164,830),"%d %s" % [slot+1,mission.weapon_profiles[p.loadout[slot]].name],13,GOLD if slot==p.active_slot else DIM,155)
	text_at(Vector2(520,853),"TAP Q: SMART ORDER / HOLD Q: DETAILS",12,DIM,485)
	if mission.squad.enabled:
		panel(Rect2(355,738,730,25))
		text_at(Vector2(373,756),mission.squad.status,12,GOLD if mission.squad.outcome=="BLOCKED" else MINT,690)
		if not mission.command_open: text_at(Vector2(510,628),mission.squad.hint,13,MINT,550)
	if mission.radio_timer>0:
		panel(Rect2(355,680,730,54))
		draw_rect(Rect2(355,680,3,54),MINT)
		text_at(Vector2(373,712),mission.localized_radio(),15,INK,690)
	if mission.objective_index<3 and p.position.distance_to(mission.objective_position())<4.0 and not is_instance_valid(p.vehicle):
		panel(Rect2(530,540,380,75))
		text_at(Vector2(550,571),tr("HOLD E / %s") % tr(mission.phase),16,GOLD,340)
		bar(Rect2(550,592,340,4),mission.interact_progress/mission.objectives[mission.objective_index].hold,GOLD)
	elif is_instance_valid(p.vehicle):
		panel(Rect2(460,105,520,91))
		text_at(Vector2(477,184),"V view / F seats / J vehicle / G ramp / L secure / O drop",12,DIM,485)
		text_at(Vector2(477,132),tr(p.vehicle.display_name)+"  /  %d km/h  /  %d%%" % [absf(p.vehicle.speed)*3.6,p.vehicle.health/p.vehicle.max_health*100],16,MINT,485)
		var hint="WASD DRIVE / E DISMOUNT / Q CREW ORDERS"
		if p.vehicle_seat==-2: hint="WASD WALK / F SEATS / E EXIT"
		elif p.vehicle.kind=="CARGO" and p.vehicle_seat==0: hint="W/S THROTTLE / A/D TURN / SPACE CLIMB / C DESCEND"
		elif p.vehicle_seat>0: hint="M DESTINATION / F SEATS / PASSENGERS CAN FIRE"
		text_at(Vector2(477,157),hint,12,DIM,485)
		if p.vehicle.kind=="CARGO":
			panel(Rect2(460,200,520,35))
			text_at(Vector2(477,224),tr("THROTTLE %d%% / CARGO %d / RAMP %s") % [p.vehicle.throttle*100,p.vehicle.logistics.cargo.size(),tr("Open" if p.vehicle.logistics.doors_open else "Closed")],12,MINT,485)
	else:
		var nearby=mission.nearest_vehicle()
		if is_instance_valid(nearby):
			panel(Rect2(510,555,420,42))
			text_at(Vector2(530,584),tr("E / USE %s") % tr(nearby.display_name),16,MINT,380)
	if mission.extract_progress>0:
		panel(Rect2(530,540,380,75))
		text_at(Vector2(559,571),"EXTRACTING  /  HOLD POSITION",17,MINT)
		bar(Rect2(550,592,340,4),mission.extract_progress/3,MINT)
	if mission.damage_flash>0:
		var a: float = mission.damage_flash*0.3
		draw_rect(Rect2(0,0,1440,900),Color(0.55,0.08,0.04,a*0.5))
		draw_rect(Rect2(0,0,1440,12),Color(0.8,0.18,0.08,a))
		draw_rect(Rect2(0,888,1440,12),Color(0.8,0.18,0.08,a))

func _draw_compass() -> void:
	var bearing = fposmod(rad_to_deg(-mission.player.rotation.y),360)
	var width = 520.0
	draw_rect(Rect2(460,18,width,54),Color(0.03,0.06,0.05,0.63))
	for i in range(-18,55):
		var angle = i*10.0
		var offset = wrapf(angle-bearing,-180,180)*4.0
		if absf(offset)>width/2-10: continue
		var x = 720+offset
		line(Vector2(x,23),Vector2(x,31 if i%3 else 36),DIM)
		if i%9==0:
			var cardinal: String = ["N","E","S","W"][posmod(i/9,4)]
			text_at(Vector2(x-5,54),cardinal,14,INK)
		elif i%3==0: text_at(Vector2(x-10,52),"%03d" % posmod(int(angle),360),11,DIM)
	draw_colored_polygon(PackedVector2Array([Vector2(715,17),Vector2(725,17),Vector2(720,24)]),GOLD)
	text_at(Vector2(702,90),"%03d" % bearing,14,GOLD)

func _draw_markers() -> void:
	var camera: Camera3D = mission.player.camera
	var target: Vector3 = mission.objective_position()+Vector3.UP*2
	if not camera.is_position_behind(target):
		var pos = camera.unproject_position(target)/view_scale
		pos.x = clampf(pos.x,370,1090)
		pos.y = clampf(pos.y,140,620)
		var points = PackedVector2Array([pos+Vector2(0,-8),pos+Vector2(7,0),pos+Vector2(0,8),pos+Vector2(-7,0),pos+Vector2(0,-8)])
		draw_polyline(points,GOLD,1.4,true)
		text_at(pos+Vector2(13,5),tr("%dm") % mission.player.position.distance_to(target),13,GOLD)
	for actor in mission.actors:
		if not actor.friendly or actor.health<=0: continue
		var point: Vector3 = actor.global_position+Vector3.UP*2.3
		if camera.is_position_behind(point): continue
		var pos = camera.unproject_position(point)/view_scale
		if pos.x<20 or pos.x>1420 or pos.y<120 or pos.y>650: continue
		text_at(pos+Vector2(-25,0),actor.call_sign,11,MINT)
		draw_circle(pos+Vector2(0,8),2.5,MINT)
	if mission.command_marker_time>0:
		var point: Vector3 = mission.command_point+Vector3.UP
		if not camera.is_position_behind(point):
			var pos = camera.unproject_position(point)/view_scale
			line(pos-Vector2(6,0),pos+Vector2(6,0),MINT,2)
			line(pos-Vector2(0,6),pos+Vector2(0,6),MINT,2)
			text_at(pos+Vector2(10,0),"SQUAD MARK",11,MINT)

func _draw_scope() -> void:
	var c=Vector2(720,450)
	var radius=284.0
	# Mask the peripheral image, retaining the actual magnified camera image.
	for i in range(64):
		var a=float(i)/64*TAU
		var b=float(i+1)/64*TAU
		var u=Vector2(cos(a),sin(a))
		var v=Vector2(cos(b),sin(b))
		draw_colored_polygon(PackedVector2Array([c+u*radius,c+v*radius,c+v*2000,c+u*2000]),Color(0.015,0.021,0.018,0.985))
	draw_arc(c,radius,0,TAU,96,Color(0.06,0.08,0.07),10,true)
	line(c-Vector2(radius,0),c+Vector2(radius,0),Color(0.025,0.03,0.025),1)
	line(c-Vector2(0,radius),c+Vector2(0,radius),Color(0.025,0.03,0.025),1)
	for i in range(-5,6):
		if i==0: continue
		draw_circle(c+Vector2(i*29,0),2,Color(0.03,0.04,0.03))
		draw_circle(c+Vector2(0,i*29),2,Color(0.03,0.04,0.03))
	draw_circle(c,1.6,Color(0.85,0.18,0.10))
	text_at(Vector2(635,690),mission.player.weapon.name,14,DIM,220)

func _draw_inventory() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.025,0.045,0.038,0.97))
	text_at(Vector2(90,74),"FIELD ARMOURY",34,GOLD)
	text_at(Vector2(90,105),"All portable weapons unlocked. Select a slot, then select a weapon.",16,DIM)
	for slot in range(3):
		var rect=Rect2(90+slot*420,125,400,64)
		panel(rect)
		if slot==mission.inventory_slot: draw_rect(rect,GOLD,false,2)
		text_at(rect.position+Vector2(18,39),"%d / %s" % [slot+1,mission.weapon_profiles[mission.player.loadout[slot]].name],21,INK,360)
	var portable=mission.weapon_profiles.filter(func(w): return w.portable)
	var selected=mission.player.loadout[mission.inventory_slot]
	var pointer=get_global_mouse_position()/view_scale
	for i in range(portable.size()):
		var spec: Dictionary=portable[i]
		var rect=Rect2(90+(i%6)*211,235+(i/6)*76,195,67)
		draw_rect(rect,Color(0.18,0.25,0.20) if rect.has_point(pointer) else PANEL)
		draw_rect(rect,GOLD if spec.id==selected else Color(0.3,0.4,0.32),false,2 if spec.id==selected else 1)
		text_at(rect.position+Vector2(12,27),spec.name,18,GOLD if spec.id==selected else INK,173)
		text_at(rect.position+Vector2(12,51),"%s / %d" % [tr(spec.category),spec.capacity],12,DIM,173)
	var chosen: Dictionary=mission.weapon_profiles[selected]
	panel(Rect2(90,715,1250,110))
	text_at(Vector2(110,748),chosen.name+" / "+tr(chosen.category),22,GOLD,1200)
	text_at(Vector2(110,780),tr("Damage %d / Magazine %d / RPM %d / Reload %.1fs / Velocity %d m/s") % [chosen.damage,chosen.capacity,60.0/chosen.interval,chosen.reload,chosen.speed],16,INK,1200)
	text_at(Vector2(110,807),"M2HB is a fixed weapon. Find emplacements at villages and the airfield.",13,DIM,1200)
	text_at(Vector2(90,863),"1 / 2 / 3 SELECT SLOT / CLICK TO EQUIP / B OR ESC RETURN",15,MINT)

func _draw_commands() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.02,0.04,0.03,0.63))
	var target=mission.command_context.get("vehicle")
	var options=mission.command_options()
	panel(Rect2(250,210,940,300 if is_instance_valid(target) else 410))
	text_at(Vector2(280,253),target.display_name if is_instance_valid(target) else "SQUAD ORDERS",26,GOLD,850)
	var names={"BOARD":"Board this vehicle","DISEMBARK":"Dismount this vehicle","MOVE":"Move / choose destination" if is_instance_valid(target) and target.kind!="CARGO" else "Move to crosshair","FOLLOW":"Follow the leader","HOLD":"Hold current positions","ATTACK":"Attack at crosshair"}
	if is_instance_valid(target) and target.kind=="CARGO":
		names.MOVE="Load transport automatically"
		if mission.squad.enabled and not target.logistics.cargo.is_empty(): names.DISEMBARK="Unload and regroup"
	for i in range(options.size()): button(Rect2(280+(i%3)*290,285+(i/3)*104,275,83),str(i+1)+" / "+tr(names[options[i]]))
	text_at(Vector2(280,470 if is_instance_valid(target) else 570),"Tap Q runs the full task. Hold Q for details. Follow cancels.",14,DIM,850)

func _draw_seats() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.02,0.04,0.03,0.78))
	var v=mission.seat_menu
	panel(Rect2(410,115,620,680))
	text_at(Vector2(440,158),v.display_name,26,GOLD,550)
	text_at(Vector2(440,187),"Choose a seat / number keys / Esc closes",14,DIM,550)
	for i in range(v.seat_count):
		var label=str(i+1)+" / "+tr(v.seat_label(i))
		if is_instance_valid(v.occupants[i]): label+=" / "+tr("Occupied")
		elif v.reservations.has(i): label+=" / "+tr("Reserved")
		button(Rect2(440,205+i*62,560,52),label)
	if v.kind in ["TRUCK","CARGO"]: button(Rect2(440,205+v.seat_count*62,560,52),str(v.seat_count+1)+" / "+tr("Walk inside the cargo area"))
	text_at(Vector2(440,757),"E dismounts. F changes seats. Passengers can fire.",14,DIM,560)

func _draw_vehicle_selection() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.02,0.04,0.03,0.91))
	panel(Rect2(280,50,880,790))
	text_at(Vector2(310,97),"SELECT COMMAND VEHICLE",26,GOLD,820)
	for i in range(mission.vehicles.size()):
		var v=mission.vehicles[i]
		var label=tr(v.display_name)+" / %.0f m" % v.position.distance_to(mission.player.position)
		if is_instance_valid(v.occupants[0]): label+=" / "+tr("Driver aboard")
		if v.logistics.secured: label+=" / "+tr("Cargo secured")
		button(Rect2(310,125+i*54,820,48),label,v==mission.selected_vehicle)
	text_at(Vector2(310,817),"Aim + Q: board / dismount / move. G: local ramp only.",14,DIM,820)

func _clamp_map() -> void:
	var margin=mission.field.LIMIT-map_width/2
	map_centre=map_centre.clamp(Vector2.ONE*-margin,Vector2.ONE*margin)

func zoom_map(factor: float,pointer: Vector2) -> void:
	# Retain the geographic position under the pointer while continuously zooming.
	if not _on_map(pointer): pointer=Vector2(770,440)
	var anchor=(pointer-Vector2(440,110))/660
	var world=map_origin()+anchor*map_width
	map_width=clampf(map_width*factor,256,mission.field.LIMIT*2)
	map_centre=world+(Vector2.ONE*0.5-anchor)*map_width
	_clamp_map()

func map_span() -> float:
	return map_width

func map_origin() -> Vector2:
	return map_centre-Vector2.ONE*map_width/2

func map_point(p: Vector3) -> Vector2:
	return Vector2(440,110)+(Vector2(p.x,p.z)-map_origin())/map_span()*660

func _on_map(p: Vector2) -> bool:
	return Rect2(440,110,660,660).has_point(p)

func _draw_map() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.02,0.04,0.035,0.98))
	text_at(Vector2(60,75),"TACTICAL PLOT",30,GOLD)
	text_at(Vector2(60,108),"KISKA ISLAND / 49.152 x 49.152 km",14,DIM)
	draw_rect(Rect2(440,110,660,660),Color(0.11,0.16,0.12))
	var source_rect=Rect2((map_origin()+Vector2.ONE*mission.field.LIMIT)/(mission.field.LIMIT*2)*mission.field.map_texture.get_width(),Vector2.ONE*map_span()/(mission.field.LIMIT*2)*mission.field.map_texture.get_width())
	draw_texture_rect_region(mission.field.map_texture,Rect2(440,110,660,660),source_rect)
	for i in range(12):
		line(Vector2(440+i*60,110),Vector2(440+i*60,770),Color(0.3,0.4,0.3,0.35))
		line(Vector2(440,110+i*60),Vector2(1100,110+i*60),Color(0.3,0.4,0.3,0.35))
		if i<11: draw_string(font,Vector2(460+i*60,99),String.chr(65+i),HORIZONTAL_ALIGNMENT_LEFT,-1,12,DIM)
	var world_rect=Rect2(map_origin(),Vector2.ONE*map_span())
	for rect in mission.field.structures:
		if not world_rect.intersects(rect): continue
		var clipped: Rect2=world_rect.intersection(rect)
		var p=map_point(Vector3(clipped.position.x,0,clipped.position.y))
		draw_rect(Rect2(p,clipped.size/map_span()*660),Color(0.5,0.51,0.38))
	for z in range(int(mission.field.sites[-1].position.z),int(mission.field.sites[0].position.z),32):
		var a=map_point(Vector3(mission.field.road_x(z),0,z))
		var b=map_point(Vector3(mission.field.road_x(z+32),0,z+32))
		if _on_map(a) and _on_map(b): line(a,b,Color(0.56,0.49,0.31),3)
	for site in mission.field.sites:
		var p=map_point(site.position)
		if not _on_map(p): continue
		draw_circle(p,3.0,DIM)
		if map_zoom: text_at(p+Vector2(10,-8),site.name,12,INK,170)
	for i in range(mission.objectives.size()):
		var p=map_point(mission.objectives[i].position)
		if not _on_map(p): continue
		var color=MINT if i<mission.objective_index else GOLD
		draw_circle(p,7 if map_zoom else 3,color,false,2)
		if map_zoom: text_at(p+Vector2(-24,5),str(i+1),13,color,24)
	for v in mission.vehicles:
		var p=map_point(v.position)
		if v.health>0 and _on_map(p): draw_rect(Rect2(p-Vector2(3,3),Vector2(6,6)),Color(0.44,0.65,0.84))
	for actor in mission.actors:
		if actor.health<=0 or is_instance_valid(actor.vehicle): continue
		var p=map_point(actor.position)
		if not _on_map(p): continue
		if actor.friendly:
			draw_circle(p,3.5,MINT)
			if map_zoom: text_at(p+Vector2(-3,-8),actor.call_sign.left(1),10,MINT,20)
		elif actor.visible_target and actor.awareness>0.5: draw_circle(p,3.5,Color(0.85,0.39,0.24))
	if not map_zoom:
		var volcano=map_point(Vector3(10429,0,-13768))
		draw_circle(volcano,4,GOLD,false,1.5)
		text_at(volcano+Vector2(-125,-15),"Kiska volcano",13,INK,150)
		var harbor=map_point(Vector3(7500,0,1000))
		text_at(harbor+Vector2(30,-14),"Kiska harbor",13,INK,150)
		var zone=map_point(Vector3(4500,0,700))
		draw_rect(Rect2(zone,Vector2(3100,4900)/map_span()*660),GOLD,false,1.0)
		text_at(Vector2(1140,244),"Harbor operation area",14,GOLD,230)
		text_at(Vector2(1140,277),"Real relief / fictional camps",13,DIM,230)
	var pp=map_point(mission.player.position)
	var forward=Vector2(sin(-mission.player.rotation.y),-cos(mission.player.rotation.y))
	draw_circle(pp,5,INK)
	line(pp,pp+forward*20,INK,2)
	if mission.command_marker_time>0:
		var p=map_point(mission.command_point)
		if _on_map(p): draw_circle(p,9,MINT,false,2)
	text_at(Vector2(60,204),"MISSION",15,DIM)
	text_at(Vector2(60,238),mission.phase,22,INK,330)
	text_at(Vector2(60,276),mission.objectives[mission.objective_index].brief,14,DIM,330)
	text_at(Vector2(60,350),"CLICK THE MAP",16,MINT,330)
	text_at(Vector2(60,382),"Send your squad to a grid mark.",15,DIM,330)
	text_at(Vector2(60,448),"SIMULATION PAUSED",15,GOLD)
	if is_instance_valid(mission.selected_vehicle): text_at(Vector2(60,535),mission.selected_vehicle.display_name,18,MINT,330)
	text_at(Vector2(60,480),"M or ESC to return to the field.",15,DIM,330)
	button(Rect2(1140,110,230,44),"Island overview" if map_zoom else "Player / 1 km")
	text_at(Vector2(1140,191),"SCROLL OR PINCH / ZOOM",13,DIM,230)
	text_at(Vector2(1140,220),"RIGHT DRAG / PAN",13,DIM,230)
	text_at(Vector2(440,815),tr("GRID %.0f m / NORTH UP / BLUE: VEHICLES") % (map_span()/11),13,DIM,660)
