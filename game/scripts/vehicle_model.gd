extends RefCounted
## Original procedural vehicle art. Cab openings remain free of opaque glass.
var v: Node3D
var f: Node3D
var root: Node3D
var paint: Material
var dark: Material
var metal: Material
var rubber: Material

func part(p: Vector3,s: Vector3,m: Material=null,parent: Node3D=null) -> Node3D:
	return f.box(root if parent==null else parent,p,s,paint if m==null else m)

func cylinder(parent: Node3D,p: Vector3,r: float,h: float,m: Material,axis_z=false) -> MeshInstance3D:
	var mesh=MeshInstance3D.new()
	var shape=CylinderMesh.new()
	shape.top_radius=r; shape.bottom_radius=r; shape.height=h; shape.radial_segments=16
	mesh.mesh=shape; mesh.material_override=m
	parent.add_child(mesh); mesh.position=p
	if axis_z: mesh.rotation.z=PI/2
	return mesh

func build(vehicle: Node3D) -> void:
	v=vehicle; f=v.mission.field; root=v.visuals
	v.cab_frame=Node3D.new(); v.cab_frame.name="CabFrame"; root.add_child(v.cab_frame)
	paint=f.mat("vehicle",Color(0.22,0.28,0.20))
	dark=f.mat("vehicle_dark",Color(0.075,0.09,0.085))
	metal=f.mat("vehicle_metal",Color(0.38,0.40,0.36),0.45)
	rubber=f.mat("vehicle_tire",Color(0.045,0.052,0.05))
	if v.kind=="HMG":
		part(Vector3(0,1.55,0),Vector3(0.23,0.26,0.6),dark)
		cylinder(root,Vector3(0,1.58,-0.75),0.045,1.1,dark).rotation.x=PI/2
		part(Vector3(-0.3,1.48,0),Vector3(0.4,0.32,0.32))
		for x in [-1,1]: part(Vector3(x*0.32,0.7,0.2),Vector3(0.055,1.4,0.055),metal).rotation.z=x*0.4
	elif v.kind=="HELI": _helicopter()
	elif v.kind=="CARGO": _cargo_plane()
	elif v.kind=="TRUCK": _truck()
	elif v.kind=="TANK": _tank()
	else: _wheeled()
	f._batch_static_geometry(root)

func _wheeled() -> void:
	var apc=v.kind=="APC"
	var width=2.55 if apc else 1.82
	var length=5.15 if apc else 3.85
	part(Vector3(0,0.53,0),Vector3(width,0.20,length),dark)
	part(Vector3(0,0.84,0.15),Vector3(width,0.38,length-0.2))
	if apc:
		part(Vector3(0,1.48,0.55),Vector3(2.5,0.95,3.5))
		part(Vector3(0,2.00,0.45),Vector3(2.45,0.13,3.4))
		part(Vector3(0,1.17,-1.72),Vector3(2.48,0.42,1.4)).rotation.x=-0.18
		cylinder(root,Vector3(0,2.19,-0.3),0.53,0.28,dark)
		part(Vector3(0,2.47,-0.85),Vector3(0.14,0.15,1.7),dark)
		for side in [-1,1]:
			for z in [-0.6,0.1,0.8,1.5]: part(Vector3(side*1.29,1.57,z),Vector3(0.04,0.10,0.3),dark)
			part(Vector3(side*1.2,1.12,0.7),Vector3(0.18,0.10,3),metal)
		for z in [-1.7,0,1.7]:
			for side in [-1,1]: _wheel(side*1.34,z,0.57,z< -1)
	else:
		# Low hood, separate open cabin, seats and dashboard below eye height.
		part(Vector3(0,1.02,-1.12),Vector3(1.78,0.18,1.42))
		part(Vector3(0,1.08,1.50),Vector3(1.80,0.42,0.55))
		part(Vector3(0,1.14,-0.31),Vector3(1.65,0.23,0.17),dark)
		for side in [-1,1]:
			part(Vector3(side*0.88,0.95,0.5),Vector3(0.10,0.38,2.0))
			part(Vector3(side*0.86,1.75,-0.90),Vector3(0.028,1.10,0.028),dark,v.cab_frame).rotation.x=0.12
			part(Vector3(side*0.86,1.6,1.3),Vector3(0.06,1.0,0.06),dark)
			for z in [0.15,1.0]:
				part(Vector3(side*0.46,0.90,z),Vector3(0.61,0.17,0.6),dark)
				part(Vector3(side*0.46,1.15,z+0.23),Vector3(0.61,0.52,0.12),dark).rotation.x=-0.10
			for z in [-1.29,1.31]:
				part(Vector3(side*0.98,0.94,z),Vector3(0.28,0.10,0.98))
				_wheel(side*1.0,z,0.46,z<0)
			part(Vector3(side*1.03,1.50,-0.40),Vector3(0.18,0.20,0.08),metal)
		part(Vector3(0,2.32,-0.98),Vector3(1.76,0.025,0.032),dark,v.cab_frame)
		part(Vector3(0,2.09,1.30),Vector3(1.76,0.06,0.06),dark)
		var steering=MeshInstance3D.new()
		var torus=TorusMesh.new(); torus.inner_radius=0.16; torus.outer_radius=0.19; torus.rings=12; torus.ring_segments=6
		steering.mesh=torus; steering.material_override=rubber; root.add_child(steering)
		steering.position=Vector3(-0.46,1.26,-0.12); steering.rotation.x=0.9
		for i in range(7): part(Vector3((i-3)*0.14,0.87,-1.91),Vector3(0.055,0.28,0.045),dark)
	# Bumpers, lamps, bonnet catches, rear brake lights and aerial.
	for z in [-1,1]: part(Vector3(0,0.65,z*(length/2+0.08)),Vector3(width+0.2,0.16,0.16),dark)
	for side in [-1,1]:
		part(Vector3(side*(width/2-0.22),0.94,-length/2-0.01),Vector3(0.25,0.20,0.035),f.mat("headlamp",Color(0.80,0.79,0.60)))
		part(Vector3(side*(width/2-0.18),0.97,length/2+0.01),Vector3(0.14,0.17,0.035),f.mat("tail_lamp",Color(0.55,0.10,0.06)))
		part(Vector3(side*(width/2-0.1),1.10,-1.1),Vector3(0.04,0.08,0.16),metal)
	cylinder(root,Vector3(width/2-0.1,2.05,1.3),0.012,1.9,dark)

func _wheel(x: float,z: float,radius: float,front: bool) -> void:
	var pivot=Node3D.new(); root.add_child(pivot); pivot.position=Vector3(x,radius,z)
	var roll=Node3D.new(); pivot.add_child(roll)
	cylinder(roll,Vector3.ZERO,radius,0.31,rubber,true)
	cylinder(roll,Vector3(0.17*signf(x),0,0),radius*0.52,0.035,metal,true)
	for i in range(8):
		var angle=i*TAU/8
		part(Vector3(signf(x)*0.196,sin(angle)*radius*0.34,cos(angle)*radius*0.34),Vector3(0.025,0.045,0.045),dark,roll)
	f._batch_static_geometry(roll)
	v.wheels.append({"pivot":pivot,"roll":roll,"x":x,"z":z,"radius":radius,"front":front})

func _helicopter() -> void:
	# Rounded central fuselage and tail; open cockpit windows ahead of the cabin.
	var shell=MeshInstance3D.new(); var capsule=CapsuleMesh.new()
	capsule.radius=1.04; capsule.height=4.0; capsule.radial_segments=16; capsule.rings=4
	shell.mesh=capsule; shell.material_override=paint; root.add_child(shell)
	shell.position=Vector3(0,1.42,0.6); shell.rotation.x=PI/2
	part(Vector3(0,0.72,-1.85),Vector3(1.9,0.22,1.5))
	part(Vector3(0,2.55,-1.95),Vector3(1.9,0.10,1.4),paint,v.cab_frame)
	for side in [-1,1]:
		part(Vector3(side*0.96,1.65,-2.55),Vector3(0.055,1.8,0.055),metal,v.cab_frame)
		part(Vector3(side*0.96,1.60,-1.40),Vector3(0.055,1.8,0.055),metal,v.cab_frame)
		part(Vector3(side*1.4,0.20,0),Vector3(0.10,0.10,4.8),dark)
		for z in [-1.3,1.3]: part(Vector3(side*1.14,0.47,z),Vector3(0.08,0.65,0.08),metal).rotation.z=side*0.4
		part(Vector3(side*0.47,1.02,-1.72),Vector3(0.66,0.15,0.65),dark)
		part(Vector3(side*0.47,1.30,-1.40),Vector3(0.66,0.55,0.12),dark)
	part(Vector3(0,1.03,-2.22),Vector3(1.6,0.14,0.35),dark)
	part(Vector3(0,1.55,3.72),Vector3(0.35,0.40,4.2))
	part(Vector3(0,2.5,5.35),Vector3(0.10,2.0,0.7))
	part(Vector3(0,1.6,4.7),Vector3(2.4,0.08,0.52))
	cylinder(root,Vector3(0,2.95,0),0.13,0.65,metal)
	v.rotor=Node3D.new(); root.add_child(v.rotor); v.rotor.position=Vector3(0,3.25,0)
	for i in range(4):
		var blade=part(Vector3.ZERO,Vector3(0.20,0.045,5.4),dark,v.rotor)
		blade.position=Vector3(sin(i*PI/2)*2.7,0,cos(i*PI/2)*2.7); blade.rotation.y=i*PI/2


func _truck() -> void:
	part(Vector3(0,0.64,0),Vector3(2.6,0.3,8.6),dark)
	part(Vector3(0,1.15,1),Vector3(2.8,0.18,5.6))
	part(Vector3(0,1.45,-3.1),Vector3(2.6,0.8,2.0))
	part(Vector3(0,2.94,-3.0),Vector3(2.7,0.12,2.0))
	part(Vector3(0,2.15,-2.04),Vector3(2.6,1.5,0.10))
	for side in [-1,1]:
		part(Vector3(side*1.31,2.12,-3.95),Vector3(0.045,1.55,0.045),dark,v.cab_frame)
		part(Vector3(side*1.38,1.68,1),Vector3(0.12,1.0,5.5))
		part(Vector3(side*0.65,1.68,-3),Vector3(0.75,0.2,0.65),dark)
		for z in [-2.8,1.5,3.3]: _wheel(side*1.42,z,0.63,z<0)
		part(Vector3(side*1.05,1.8,-4.12),Vector3(0.32,0.22,0.04),metal)
	for i in range(7): part(Vector3((i-3)*0.23,1.32,-4.12),Vector3(0.08,0.40,0.06),dark)
	part(Vector3(0,0.85,-4.3),Vector3(3,0.2,0.16),dark)

func _tank() -> void:
	part(Vector3(0,0.85,0),Vector3(3.4,0.75,6.8))
	part(Vector3(0,1.35,0),Vector3(3.0,0.3,6.0))
	part(Vector3(0,1.95,-0.1),Vector3(2.35,0.95,2.7))
	cylinder(root,Vector3(0,2.52,0),0.52,0.15,dark)
	var barrel=cylinder(root,Vector3(0,2.05,-3.1),0.13,4.2,paint); barrel.rotation.x=PI/2
	part(Vector3(0,2.05,-5.3),Vector3(0.25,0.24,0.35),dark)
	for side in [-1,1]:
		part(Vector3(side*1.55,0.48,0),Vector3(0.48,0.82,6.3),rubber)
		for z in [-2.5,-1.5,-0.5,0.5,1.5,2.5]: _wheel(side*1.63,z,0.46,z< -2)
		for z in [-2.4,-1.2,0,1.2,2.4]: part(Vector3(side*1.72,1.12,z),Vector3(0.12,0.45,1.0))
		part(Vector3(side*0.88,2.1,0.1),Vector3(0.4,0.25,1.5),metal)

func _cargo_plane() -> void:
	paint=f.mat("airframe",Color(0.42,0.46,0.44))
	var inner=f.mat("cargo_inner",Color(0.40,0.43,0.39))
	var lamp=f.mat("cargo_lamp",Color(0.80,0.88,0.82))
	lamp.emission_enabled=true; lamp.emission=Color(0.65,0.75,0.68)
	for z in [-11,0,11]:
		part(Vector3(0,8.9,z),Vector3(1.4,0.08,0.35),lamp)
		var light=OmniLight3D.new(); root.add_child(light)
		light.position=Vector3(0,7.7,z); light.light_color=Color(0.86,0.92,0.88)
		light.light_energy=3.0; light.omni_range=14; light.shadow_enabled=false
	part(Vector3(0,1.0,-1),Vector3(10,0.4,36),inner)
	for side in [-1,1]:
		part(Vector3(side*4.9,5.2,-2),Vector3(0.35,8.4,38))
		for z in range(-16,17,4):
			part(Vector3(side*4.65,5.2,z),Vector3(0.18,8.0,0.16),metal)
			part(Vector3(side*2.8,1.22,z),Vector3(0.12,0.025,1.1),metal)
		# Broad swept wings and two engine nacelles per wing.
		part(Vector3(side*21,6.3,0),Vector3(33,0.50,7.3)).rotation.y=side*0.12
		for x in [14,25]:
			var engine=cylinder(root,Vector3(side*x,3.8,-1),1.8,5.5,paint); engine.rotation.x=PI/2
			var fan=cylinder(root,Vector3(side*x,3.8,-3.82),1.5,0.12,dark); fan.rotation.x=PI/2
			part(Vector3(side*x,5.4,-0.4),Vector3(0.35,2.4,2.5),metal)
		for z in [7,10]: _wheel(side*3.65,z,0.72,false)
	part(Vector3(0,9.3,-2),Vector3(10,0.35,38))
	part(Vector3(0,3.0,-22.2),Vector3(9.2,3.6,7.0))
	part(Vector3(0,6.5,-22),Vector3(9.0,0.15,6.5))
	part(Vector3(0,4.65,-25.5),Vector3(0.06,3.6,0.06),metal,v.cab_frame)
	for side in [-1,1]: part(Vector3(side*4.3,4.8,-25.3),Vector3(0.08,3.1,0.08),metal,v.cab_frame)
	part(Vector3(0,3.5,-18.9),Vector3(9.5,4.5,0.2),inner)
	part(Vector3(0,9.2,23),Vector3(2.2,2.0,13))
	part(Vector3(0,13.0,26),Vector3(0.55,11,6))
	part(Vector3(0,17.4,26),Vector3(24,0.4,4.5))
	_wheel(0,-22,0.72,true)
	v.door_visual=Node3D.new(); root.add_child(v.door_visual)
	part(Vector3(0,5.2,17),Vector3(9.6,8.0,0.25),paint,v.door_visual)
	v.ramp_visual=Node3D.new(); root.add_child(v.ramp_visual); v.ramp_visual.visible=false
	var ramp=part(Vector3(0,0.6,21.5),Vector3(9.5,0.18,9.2),inner,v.ramp_visual); ramp.rotation.x=0.13
	for i in range(12): part(Vector3(0,1.15-float(i)*0.10,17+i*0.76),Vector3(9.1,0.045,0.07),metal,v.ramp_visual)
