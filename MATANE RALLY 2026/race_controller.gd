extends CanvasLayer
# ==============================================================================
# RaceController.gd
# Attach to a CanvasLayer node in your stage scene.
# ==============================================================================

@export_group("References")
@export var stage_start: Node
@export var copilot:     Node
@export var car:         RigidBody3D
@export var slow_zone:   Area3D

@export_group("Retry")
@export var retry_position: Vector3
@export var retry_rotation: Vector3

@export_group("Penalty")
@export var penalty_seconds:          float = 5.0
@export var penalty_display_duration: float = 3.0

# ==============================================================================
# INTERNAL
# ==============================================================================

const SAVE_PATH := "user://best_times.cfg"

var _running:       bool  = false
var _finished:      bool  = false
var _elapsed:       float = 0.0
var _penalties:     float = 0.0
var _penalty_timer: float = 0.0
var _last_note_idx: int   = -1
var _best_time:     float = -1.0
var _stage_id:      String = "stage_01"

# UI
@export var _timer_label:   Label
@export var _penalty_label: Label
@export var _result_label:  Label
@export var _diff_label:    Label
@export var _best_label:    Label
@export var _retry_button:  Button
@export var _prompt_label:  Label # NEW: Assign a Label for "HOLD HANDBRAKE"

# ==============================================================================
# READY
# ==============================================================================

func _ready() -> void:
	_load_best_time()

	_penalty_label.visible = false
	_result_label.visible  = false
	_diff_label.visible    = false
	_best_label.visible    = false
	_retry_button.visible  = false
	
	if _prompt_label:
		_prompt_label.visible = false
		
	_timer_label.text      = "00:00.00"

	_retry_button.pressed.connect(_on_retry)

	if stage_start:
		stage_start.car_released.connect(_on_car_released)
		# Connect new signals for the handbrake UI
		stage_start.waiting_for_handbrake.connect(_on_waiting_for_handbrake)
		stage_start.countdown_started.connect(_on_countdown_started)
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
# PROCESS & TIMER
# ==============================================================================

func _process(delta: float) -> void:
	if _running and not _finished:
		_elapsed += delta
		_update_timer_display(_elapsed + _penalties, _timer_label)

	if _penalty_timer > 0.0:
		_penalty_timer -= delta
		if _penalty_timer <= 0.0:
			_penalty_label.visible = false

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

func _on_waiting_for_handbrake() -> void:
	if _prompt_label:
		_prompt_label.text = "PULL HANDBRAKE TO START"
		_prompt_label.visible = true

func _on_countdown_started() -> void:
	if _prompt_label:
		_prompt_label.visible = false

func _on_car_released() -> void:
	_running = true
	print("[RaceController] Timer started.")

func _on_note_called(note) -> void:
	if not _running or _finished:
		return
	var notes = copilot.note_book.notes
	for i in range(notes.size()):
		if notes[i] == note:
			if _last_note_idx >= 0 and i > _last_note_idx + 1:
				var missed_count  = i - _last_note_idx - 1
				var batch_penalty = missed_count * penalty_seconds
				_penalties       += batch_penalty
				_penalty_label.text    = "+%.0fs PENALTY" % batch_penalty
				_penalty_label.visible = true
				_penalty_timer         = penalty_display_duration
			_last_note_idx = i
			break

func _on_slow_zone_entered(body: Node) -> void:
	if body != car or not _running or _finished:
		return
	_finished = true
	_running  = false
	_show_result()

# ==============================================================================
# RESULT
# ==============================================================================

func _show_result() -> void:
	var final_time = _elapsed + _penalties

	var result = "STAGE COMPLETE\n\n"
	result += "Time:          %s\n" % _format_time(_elapsed)
	if _penalties > 0.0:
		result += "Penalties:   +%.0fs\n" % _penalties
		result += "Final:         %s\n"   % _format_time(final_time)

	_result_label.text    = result
	_result_label.visible = true

	if _best_time > 0.0:
		var diff = final_time - _best_time
		if diff < 0.0:
			_diff_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
			_diff_label.text = "-%s  NEW BEST!" % _format_time(abs(diff))
			_best_label.text = "Previous best:  %s" % _format_time(_best_time)
		else:
			_diff_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
			_diff_label.text = "+%s" % _format_time(diff)
			_best_label.text = "Best:  %s" % _format_time(_best_time)
		_diff_label.visible = true
		_best_label.visible = true
	else:
		_diff_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
		_diff_label.text    = "FIRST RUN!"
		_diff_label.visible = true

	if _best_time < 0.0 or final_time < _best_time:
		_best_time = final_time
		_save_best_time()

	_timer_label.visible  = false
	_retry_button.visible = true

# ==============================================================================
# RETRY
# ==============================================================================

func _on_retry() -> void:
	_result_label.visible  = false
	_diff_label.visible    = false
	_best_label.visible    = false
	_retry_button.visible  = false
	_penalty_label.visible = false

	_running       = false
	_finished      = false
	_elapsed       = 0.0
	_penalties     = 0.0
	_penalty_timer = 0.0
	_last_note_idx = -1

	_timer_label.text    = "00:00.00"
	_timer_label.visible = true

	if car:
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze      = true
		car.linear_velocity  = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.call_deferred("set_global_position", retry_position)
		car.call_deferred("set_global_rotation_degrees", retry_rotation)

	if stage_start:
		stage_start._released         = false
		stage_start._frozen           = false
		stage_start._countdown_active = false
		stage_start._timer            = 0.0
		stage_start._car_node.input_blocked = true
		if copilot:
			copilot.stop()
			copilot.start()

# ==============================================================================
# PERSISTENCE
# ==============================================================================

func _save_best_time() -> void:
	var config = ConfigFile.new()
	config.set_value("times", _stage_id, _best_time)
	config.save(SAVE_PATH)

func _load_best_time() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		_best_time = config.get_value("times", _stage_id, -1.0)
