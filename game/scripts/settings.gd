extends Node
## Persistent preferences and data-driven translations shared by every scene.
const CONFIG_PATH = "user://settings.cfg"
const LANGUAGES = ["zh_CN", "en"]
const RENDER_SCALES = [1.0, 0.75, 0.5]
var language = "zh_CN"
var fullscreen = false
var render_scale = 1.0
var transient = false
var catalog: Dictionary = {}
var windowed_size = Vector2i(1280, 800)
var config_path = CONFIG_PATH
var weapon_slots: Array[int]=[0,30,34]

func _ready() -> void:
	var args = OS.get_cmdline_user_args()
	for flag in ["--integration-test", "--logistics-test", "--vehicle-context-test", "--autonomy-test", "--smoke-test", "--settings-test", "--capture", "--benchmark"]:
		if flag in args: transient = true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://locales/zh_CN.json"))
	if not parsed is Dictionary:
		push_error("Unable to load the Chinese translation catalog.")
		return
	catalog = parsed
	var chinese = Translation.new()
	chinese.locale = "zh_CN"
	var english = Translation.new()
	english.locale = "en"
	for key in catalog:
		chinese.add_message(key,catalog[key])
		english.add_message(key,key)
	TranslationServer.add_translation(chinese)
	TranslationServer.add_translation(english)
	if not transient: load_preferences()
	if "--english" in args: language = "en"
	for arg in args:
		if arg.begins_with("--render-scale="):
			var value = arg.trim_prefix("--render-scale=").to_float()
			if value in RENDER_SCALES: render_scale = value
	TranslationServer.set_locale(language)
	get_window().title = tr("KISKA COMMAND")
	get_window().size_changed.connect(_apply_render_scale)
	_apply_render_scale()
	if DisplayServer.get_name() != "headless":
		if "--fullscreen-preview" in args: fullscreen = true
		_apply_window_mode()

func save_preferences() -> Error:
	if transient: return OK
	var config = ConfigFile.new()
	config.set_value("interface", "language", language)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "render_scale", render_scale)
	config.set_value("equipment", "slots", weapon_slots)
	var result = config.save(config_path)
	if result != OK: push_warning("Unable to save preferences: %s" % result)
	return result

func load_preferences() -> Error:
	var config = ConfigFile.new()
	var result = config.load(config_path)
	if result != OK: return result
	language = str(config.get_value("interface", "language", "zh_CN"))
	fullscreen = bool(config.get_value("display", "fullscreen", false))
	render_scale = float(config.get_value("display", "render_scale", 1.0))
	var slots=config.get_value("equipment", "slots", [0,30,34])
	if slots is Array and slots.size()==3:
		for i in range(3):
			if int(slots[i])>=0 and int(slots[i])<35: weapon_slots[i]=int(slots[i])
	if language not in LANGUAGES: language = "zh_CN"
	if render_scale not in RENDER_SCALES: render_scale = 1.0
	TranslationServer.set_locale(language)
	_apply_render_scale()
	return OK

func set_language(locale: String) -> void:
	if locale not in LANGUAGES: return
	language = locale
	TranslationServer.set_locale(language)
	get_window().title = tr("KISKA COMMAND")
	save_preferences()

func toggle_language() -> void:
	set_language("en" if language == "zh_CN" else "zh_CN")

func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	_apply_window_mode()
	save_preferences()

func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless": return
	var window = get_window()
	if fullscreen:
		if window.mode == Window.MODE_WINDOWED: windowed_size = window.size
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		window.size = windowed_size
	_apply_render_scale()

func set_render_scale(value: float) -> void:
	if value not in RENDER_SCALES: return
	render_scale = value
	_apply_render_scale()
	save_preferences()

func cycle_render_scale() -> void:
	set_render_scale(RENDER_SCALES[(RENDER_SCALES.find(render_scale)+1)%RENDER_SCALES.size()])

func _apply_render_scale() -> void:
	# Scale only the 3D buffer. UI stays at the full window resolution.
	get_window().scaling_3d_scale = render_scale

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F10:
			toggle_language()
			get_viewport().set_input_as_handled()
