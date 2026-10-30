extends SceneTree
## Isolated preferences fixture; never overwrites the player's settings file.
var checks = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("SETTINGS_FAILED: "+label)
		quit(4)
	else:
		checks += 1
		print("CHECK: ",label)

func _run() -> void:
	var settings = root.get_node("Settings")
	check(settings.language == "zh_CN", "fresh launch defaults to Simplified Chinese")
	check(TranslationServer.translate("INFILTRATE") == "渗透接近", "Chinese catalog is active")
	check(TranslationServer.translate("%s is down. Keep moving.") % [TranslationServer.translate("BRAVO")] == "布拉沃阵亡，继续前进。", "formatted radio message translates names and template")
	settings.set_language("en")
	check(TranslationServer.translate("INFILTRATE") == "INFILTRATE", "English can be selected at runtime")
	settings.set_language("unknown")
	check(settings.language == "en", "unsupported locale is rejected")
	settings.toggle_language()
	check(TranslationServer.translate("SEIZE INTEL") == "夺取情报", "runtime toggle restores Chinese")
	var font = load("res://fonts/NotoSansSC.ttf") as Font
	check(font != null and font.has_char("中".unicode_at(0)), "bundled font contains Chinese glyphs")
	settings.set_render_scale(0.75)
	check(is_equal_approx(root.scaling_3d_scale,0.75), "resolution preference changes actual 3D buffer scale")
	settings.set_render_scale(0.6)
	check(is_equal_approx(settings.render_scale,0.75), "unsupported render scale is rejected")
	settings.config_path = "user://settings-roundtrip-test.cfg"
	settings.transient = false
	settings.fullscreen = true
	settings.weapon_slots.assign([4,31,33])
	check(settings.save_preferences() == OK, "preferences save to an isolated file")
	settings.language = "en"
	settings.fullscreen = false
	settings.render_scale = 1.0
	settings.weapon_slots.assign([0,30,34])
	check(settings.load_preferences() == OK and settings.language=="zh_CN" and settings.fullscreen and is_equal_approx(settings.render_scale,0.75), "language, fullscreen and resolution survive reload")
	check(settings.weapon_slots==[4,31,33], "all three weapon assignments survive preference reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.config_path))
	settings.transient = true
	settings.fullscreen = false
	settings.set_render_scale(1.0)
	if checks == 12: print("SETTINGS_PASS: ",checks," checks")
	quit(0 if checks == 12 else 4)
