extends Window

# ---------------------------------------------------------------------------
# OptionsMenu.gd
# Attach to a Window node (child of the MainMenu Control).
#
# Expected scene tree inside the Window:
#   Window  (this script)
#   └─ VBoxContainer
#      ├─ Label               "Volume"
#      ├─ HSlider    (name="VolumeSlider")
#      ├─ CheckButton (name="FullscreenToggle")  "Fullscreen"
#      └─ Button     (name="CloseButton")        "Close"
# ---------------------------------------------------------------------------

@onready var volume_slider:      HSlider     = $VBoxContainer/VolumeSlider
@onready var fullscreen_toggle:  CheckButton = $VBoxContainer/FullscreenToggle
@onready var close_button:       Button      = $VBoxContainer/CloseButton


func _ready() -> void:
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.value     = _load_volume()
	_apply_volume(volume_slider.value)

	fullscreen_toggle.button_pressed = _load_fullscreen()
	_apply_fullscreen(fullscreen_toggle.button_pressed)

	volume_slider.value_changed.connect(_apply_volume)
	fullscreen_toggle.toggled.connect(_apply_fullscreen)
	close_button.pressed.connect(_on_close_pressed)
	close_requested.connect(_on_close_pressed)


func _apply_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value / 100.0))
	AudioServer.set_bus_mute(0, value == 0.0)


func _apply_fullscreen(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _load_volume() -> float:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		return cfg.get_value("audio", "volume", 80.0)
	return 80.0


func _load_fullscreen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		return cfg.get_value("display", "fullscreen", false)
	return false


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio",   "volume",     volume_slider.value)
	cfg.set_value("display", "fullscreen", fullscreen_toggle.button_pressed)
	cfg.save("user://settings.cfg")


func _on_close_pressed() -> void:
	_save_settings()
	hide()
