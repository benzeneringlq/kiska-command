extends Node3D
## An open reflex/iron sight, compensated for world FOV so zoom cannot enlarge it.
var mission: Node3D
var camera: Camera3D
var profile: Dictionary
var flash: MeshInstance3D
var aim_blend=0.0
var sight_height=0.078

func rebuild(spec: Dictionary) -> void:
	profile=spec
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var dark=mission.field.mat("rifle",Color(0.075,0.095,0.09),0.55)
	var stock=mission.field.mat("weapon_stock",Color(0.27,0.30,0.22))
	var glove=mission.field.mat("gloves",Color(0.28,0.28,0.21))
	var cat: String=profile.category
	var pistol=cat=="Pistol"
	var launcher=cat=="Launcher"
	var length=0.32 if pistol else (0.8 if cat in ["Sniper","Machine gun","Shotgun"] else 0.60)
	var body=Vector3(0.19,-0.19,-0.38)
	mission.field.box(self,body,Vector3(0.09,0.13,0.30 if not pistol else 0.18),dark)
	mission.field.box(self,Vector3(0.19,-0.20,-0.58),Vector3(0.1,0.1,length*0.55),stock)
	mission.field.box(self,Vector3(0.19,-0.18,-0.55-length*0.4),Vector3(0.035,0.035,length*0.6),dark)
	mission.field.box(self,Vector3(0.19,-0.29,-0.32),Vector3(0.07,0.18,0.09),dark)
	if not pistol:
		mission.field.box(self,Vector3(0.19,-0.20,-0.14),Vector3(0.09,0.13,0.20),stock)
		mission.field.box(self,Vector3(0.19,-0.30,-0.42),Vector3(0.065,0.17,0.10),dark)
	if cat=="Machine gun": mission.field.box(self,Vector3(0.19,-0.32,-0.46),Vector3(0.23,0.20,0.20),stock)
	if launcher:
		mission.field.box(self,Vector3(0.19,-0.18,-0.48),Vector3(0.18,0.18,0.85),stock)
	# Four slim bars enclose a genuinely empty optical aperture.
	if profile.optic in ["reflex","scope"]:
		for side in [-1,1]:
			mission.field.box(self,Vector3(0.19+side*0.038,-sight_height,-0.46),Vector3(0.009,0.080,0.045),dark)
			mission.field.box(self,Vector3(0.19,-sight_height+side*0.040,-0.46),Vector3(0.085,0.009,0.045),dark)
	else:
		# Rear U-notch and front post tip stop just below the actual aim ray.
		for side in [-1,1]:
			mission.field.box(self,Vector3(0.19+side*0.025,-sight_height-0.014,-0.36),Vector3(0.009,0.035,0.035),dark)
		mission.field.box(self,Vector3(0.19,-sight_height-0.020,-0.70),Vector3(0.008,0.032,0.018),dark)
	mission.field.box(self,Vector3(0.20,-0.31,-0.23),Vector3(0.10,0.09,0.17),glove)
	if not pistol: mission.field.box(self,Vector3(0.12,-0.26,-0.58),Vector3(0.10,0.09,0.17),glove)
	var flame=mission.field.mat("flash",Color(1,0.78,0.3))
	flame.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	flash=mission.field.box(self,Vector3(0.19,-0.18,-0.6-length*0.75),Vector3(0.1,0.09,0.15),flame)
	flash.visible=false
	for mesh in get_children(): mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func pose(dt: float,aiming: bool,kick: float,reload_fraction: float,bob: float,flash_on: bool) -> void:
	aim_blend=move_toward(aim_blend,1.0 if aiming else 0.0,dt*7)
	# Scale x/y (and their offsets) to preserve the viewmodel's fixed apparent FOV.
	var ratio=tan(deg_to_rad(camera.fov)*0.5)/tan(deg_to_rad(78.0)*0.5)
	var dip=sin(reload_fraction*PI)*0.25
	scale=Vector3(ratio,ratio,1)
	position=Vector3(-0.19*aim_blend*ratio,(sight_height*aim_blend-dip+bob*(1-aim_blend))*ratio,kick*0.8)
	rotation.z=-dip*1.5
	visible=not (aiming and profile.optic=="scope" and aim_blend>0.85)
	flash.visible=flash_on

func centre_clear() -> bool:
	if profile.optic=="scope" and not visible: return true
	var origin=camera.global_position
	var end=origin-camera.global_basis.z*3.0
	for child in get_children():
		if child==flash or not child.visible: continue
		var aabb: AABB=child.get_aabb()
		if aabb.intersects_segment(child.to_local(origin),child.to_local(end))!=null: return false
	return true
