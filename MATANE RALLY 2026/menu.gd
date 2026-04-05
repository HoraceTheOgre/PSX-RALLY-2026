extends CanvasLayer

# ---------------------------------------------------------------------------
# MainMenu.gd  —  single script, no popup Window needed.
# Attach to a CanvasLayer node.
#
# Expected scene tree:
#   CanvasLayer  (this script)
#   └─ VBoxContainer
#      ├─ VBoxContainer  (name="MainPanel")
#      │  ├─ Label          (game title)
#      │  ├─ Button         (name="PlayButton")
#      │  ├─ Button         (name="OptionsButton")
#      │  └─ Button         (name="QuitButton")
#      │
#      └─ VBoxContainer  (name="OptionsPanel")
#         ├─ Label           "Volume"
#         ├─ HSlider         (name="VolumeSlider")
#         ├─ CheckButton     (name="FullscreenToggle")  "Fullscreen"
#         └─ Button          (name="BackButton")        "Back"
# ---------------------------------------------------------------------------

const GAME_SCENE := "res://Game.tscn"
const SAVE_PATH  := "user://settings.cfg"

# Main panel
@onready var main_panel:      VBoxContainer = $VBoxContainer/MainPanel
@onready var play_button:     Button        = $VBoxContainer/MainPanel/PlayButton
@onready var options_button:  Button        = $VBoxContainer/MainPanel/OptionsButton
@onready var quit_button:     Button        = $VBoxContainer/MainPanel/QuitButton

# Options panel
@onready var options_panel:      VBoxContainer = $VBoxContainer/OptionsPanel
@onready var volume_slider:      HSlider       = $VBoxContainer/OptionsPanel/VolumeSlider
@onready var fullscreen_toggle:  CheckButton   = $VBoxContainer/OptionsPanel/FullscreenToggle
@onready var back_button:        Button        = $VBoxContainer/OptionsPanel/BackButton


func _ready() -> void:
	# ── Connect signals ──────────────────────────────────────────────────
	play_button.pressed.connect(_on_play_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(_on_back_pressed)

	# ── Load saved settings ──────────────────────────────────────────────
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.value     = _load_float("audio",   "volume",     80.0)
	fullscreen_toggle.button_pressed = _load_bool("display", "fullscreen", false)

	_on_volume_changed(volume_slider.value)
	_on_fullscreen_toggled(fullscreen_toggle.button_pressed)

	# ── Start on main panel ──────────────────────────────────────────────
	_show_main()


# ── Panel switching ───────────────────────────────────────────────────────

func _show_main() -> void:
	main_panel.visible   = true
	options_panel.visible = false
	play_button.grab_focus()


func _show_options() -> void:
	main_panel.visible    = false
	options_panel.visible = true
	back_button.grab_focus()


# ── Main panel callbacks ──────────────────────────────────────────────────

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_options_pressed() -> void:
	_show_options()


func _on_quit_pressed() -> void:
	get_tree().quit()


# ── Options callbacks ─────────────────────────────────────────────────────

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value / 100.0))
	AudioServer.set_bus_mute(0, value == 0.0)


func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_back_pressed() -> void:
	_save_settings()
	_show_main()


# ── Persistence ───────────────────────────────────────────────────────────

func _load_float(section: String, key: String, default: float) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return cfg.get_value(section, key, default)
	return default


func _load_bool(section: String, key: String, default: bool) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return cfg.get_value(section, key, default)
	return default


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio",   "volume",     volume_slider.value)
	cfg.set_value("display", "fullscreen", fullscreen_toggle.button_pressed)
	cfg.save(SAVE_PATH)
