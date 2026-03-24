extends CanvasLayer

@export_group("References")
@export var stage_start: Node
@export var copilot:     Node
@export var car:         RigidBody3D
@export var slow_zone:   Area3D

@export_group("Penalty")
@export var penalty_seconds:          float = 5.0
@export var penalty_display_duration: float = 3.0

# ==============================================================================
# INTERNAL
# ==============================================================================

var _running:       bool  = false
var _finished:      bool  = false
var _elapsed:       float = 0.0
var _penalties:     float = 0.0
var _penalty_timer: float = 0.0
var _last_note_idx: int   = -1

# UI
var _timer_label:   Label
var _penalty_label: Label
var _result_label:  Label

# ==============================================================================
# READY
# ==============================================================================

func _ready() -> void:
	_build_hud()

	if stage_start:
		stage_start.car_released.connect(_on_car_released)
	else:
		push_warning("[RaceController] No stage_start assigned.")

	if copilot:
		copilot.note_called.connect(_on_note_called)
	else:
		push_warning("[RaceController] No copilot assigned.")

	if slow_zone:
		slow_zone.body_entered.connect(_on_slow_zone_entered)
	else:
		push_warning("[RaceController] No slow_zone assigned.")

# ==============================================================================
# HUD SETUP
# ==============================================================================

func _build_hud() -> void:
	# --- Timer — top right ---
	_timer_label = Label.new()
	add_child(_timer_label)
	_timer_label.add_theme_font_size_override("font_size", 52)
	_timer_label.add_theme_color_override("font_color", Color.WHITE)
	_timer_label.anchor_left         = 1.0
	_timer_label.anchor_right        = 1.0
	_timer_label.anchor_top          = 0.0
	_timer_label.anchor_bottom       = 0.0
	_timer_label.offset_left         = -320.0
	_timer_label.offset_right        = -20.0
	_timer_label.offset_top          = 20.0
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.text                = "00:00.00"

	# --- Penalty — upper center ---
	_penalty_label = Label.new()
	add_child(_penalty_label)
	_penalty_label.add_theme_font_size_override("font_size", 56)
	_penalty_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	_penalty_label.anchor_left          = 0.5
	_penalty_label.anchor_right         = 0.5
	_penalty_label.anchor_top           = 0.2
	_penalty_label.anchor_bottom        = 0.2
	_penalty_label.offset_left          = -250.0
	_penalty_label.offset_right         = 250.0
	_penalty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_penalty_label.visible              = false

	# --- Result — dead center ---
	_result_label = Label.new()
	add_child(_result_label)
	_result_label.add_theme_font_size_override("font_size", 64)
	_result_label.add_theme_color_override("font_color", Color.WHITE)
	_result_label.anchor_left          = 0.5
	_result_label.anchor_right         = 0.5
	_result_label.anchor_top           = 0.5
	_result_label.anchor_bottom        = 0.5
	_result_label.offset_left          = -400.0
	_result_label.offset_right         = 400.0
	_result_label.offset_top           = -120.0
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.visible              = false

# ==============================================================================
# PROCESS
# ==============================================================================

func _process(delta: float) -> void:
	if _running and not _finished:
		_elapsed += delta
		_update_timer_display(_elapsed + _penalties, _timer_label)

	if _penalty_timer > 0.0:
		_penalty_timer -= delta
		if _penalty_timer <= 0.0:
			_penalty_label.visible = false

# ==============================================================================
# TIMER DISPLAY
# ==============================================================================

func _update_timer_display(total_seconds: float, label: Label) -> void:
	var minutes    = int(total_seconds) / 60
	var seconds    = int(total_seconds) % 60
	var hundredths = int(fmod(total_seconds, 1.0) * 100)
	label.text = "%02d:%02d.%02d" % [minutes, seconds, hundredths]

func _format_time(total_seconds: float) -> String:
	var minutes    = int(total_seconds) / 60
	var seconds    = int(total_seconds) % 60
	var hundredths = int(fmod(total_seconds, 1.0) * 100)
	return "%02d:%02d.%02d" % [minutes, seconds, hundredths]

# ==============================================================================
# SIGNALS
# ==============================================================================

func _on_car_released() -> void:
	_running = true
	print("[RaceController] Timer started.")

func _on_note_called(note) -> void:
	if not _running or _finished:
		return
	# Find the index of the note that was just called
	var notes = copilot.note_book.notes
	for i in range(notes.size()):
		if notes[i] == note:
			# If notes were skipped since the last called one, each counts as a miss
			if _last_note_idx >= 0 and i > _last_note_idx + 1:
				var missed_count = i - _last_note_idx - 1
				for m in range(missed_count):
					add_penalty()
			_last_note_idx = i
			break

func _on_slow_zone_entered(body: Node) -> void:
	if body != car or not _running or _finished:
		return
	_finished = true
	_running  = false
	_show_result()

# ==============================================================================
# PENALTY
# ==============================================================================

func add_penalty() -> void:
	if not _running or _finished:
		return
	_penalties     += penalty_seconds
	_penalty_label.text    = "+%ds PENALTY" % int(penalty_seconds)
	_penalty_label.visible = true
	_penalty_timer = penalty_display_duration
	print("[RaceController] Penalty — total penalties: %.0fs" % _penalties)

# ==============================================================================
# RESULT
# ==============================================================================

func _show_result() -> void:
	var final_time = _elapsed + _penalties
	var result     = "STAGE COMPLETE\n\n"
	result        += "Time:  %s\n" % _format_time(_elapsed)

	if _penalties > 0.0:
		result += "Penalties:  +%.0fs\n" % _penalties
		result += "Final:  %s"           % _format_time(final_time)

	_timer_label.visible  = false
	_result_label.text    = result
	_result_label.visible = true

	print("[RaceController] Stage complete — Final: %s" % _format_time(final_time))
