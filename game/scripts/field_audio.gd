extends Node
## Original procedural sounds, generated once at startup.
var shot: AudioStreamWAV
var distant: AudioStreamWAV
var reload_sound: AudioStreamWAV
var confirm: AudioStreamWAV
var local_player: AudioStreamPlayer
var ui_player: AudioStreamPlayer
var pool: Array[AudioStreamPlayer3D] = []
var next_voice = 0
var muted_fixture = false

func _ready() -> void:
	muted_fixture = "--integration-test" in OS.get_cmdline_user_args() or "--smoke-test" in OS.get_cmdline_user_args()
	shot = synth(0.20,0)
	distant = synth(0.26,1)
	reload_sound = synth(0.35,2)
	confirm = synth(0.14,3)
	local_player = AudioStreamPlayer.new()
	local_player.max_polyphony = 6
	local_player.volume_db = -12
	add_child(local_player)
	ui_player = AudioStreamPlayer.new()
	ui_player.volume_db = -18
	add_child(ui_player)
	for i in range(16):
		var voice = AudioStreamPlayer3D.new()
		voice.max_distance = 120
		voice.unit_size = 12
		voice.volume_db = -16
		add_child(voice)
		pool.append(voice)

func synth(duration: float, kind: int) -> AudioStreamWAV:
	var rate = 22050
	var data = PackedByteArray()
	data.resize(int(duration*rate)*2)
	var rng = RandomNumberGenerator.new()
	rng.seed = 42+kind
	var filtered = 0.0
	for i in range(int(duration*rate)):
		var t = float(i)/rate
		var noise = rng.randf_range(-1,1)
		filtered = lerpf(filtered,noise,0.18 if kind==1 else 0.7)
		var value = 0.0
		if kind<=1:
			value = (filtered*0.7+sin(t*TAU*(100-t*180))*0.3)*exp(-t*28)*(minf(t*1500,1))
		elif kind==2:
			value = filtered*(exp(-t*90)+0.7*exp(-absf(t-0.22)*140))
		else:
			value = sin(t*TAU*950)*0.20*sin(t/duration*PI)
		data.encode_s16(i*2,int(clampf(value,-1,1)*30000))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

func play_shot() -> void:
	if muted_fixture: return
	local_player.stream = shot
	local_player.pitch_scale = randf_range(0.95,1.05)
	local_player.play()

func play_at(pos: Vector3) -> void:
	if muted_fixture: return
	var voice = pool[next_voice]
	next_voice = (next_voice+1)%pool.size()
	voice.global_position = pos
	voice.stream = distant
	voice.pitch_scale = randf_range(0.9,1.1)
	voice.play()

func play_reload() -> void:
	if muted_fixture: return
	ui_player.stream = reload_sound
	ui_player.play()

func beep() -> void:
	if muted_fixture: return
	ui_player.stream = confirm
	ui_player.play()

func silence() -> void:
	local_player.stop()
	ui_player.stop()
	for voice in pool: voice.stop()

func _exit_tree() -> void:
	silence()
