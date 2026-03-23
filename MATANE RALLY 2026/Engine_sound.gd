extends Node
# ==============================================================================
# EngineSound.gd
# Attach as a child of the car RigidBody3D.
# Requires two AudioStreamPlayer3D children: IdlePlayer and EnginePlayer.
# ==============================================================================

@export_group("Gears")

@export var gear_speeds: Array[float] = [0.0, 35.0, 65.0, 100.0, 140.0, 180.0, 220.0]
#controls pitch drop
@export var shift_dip_duration: float = 0.18
@export var shift_dip_amount: float   = 0.80

@export_group("Pitch")
@export var engine_pitch_min: float  = 0.85
@export var engine_pitch_max: float  = 2.10
@export var idle_pitch: float        = 0.75
@export var pitch_blend_speed: float = 5.0

@export_group("Volume")
@export var engine_volume_full_db: float = 0.0
@export var engine_volume_idle_db: float = -12.0
@export var idle_volume_run_db: float    = -6.0
@export var volume_blend_speed: float    = 5.0

# ==============================================================================
# INTERNAL
# ==============================================================================

@export var _idle:   AudioStreamPlayer3D
@export var _engine: AudioStreamPlayer3D

var _car:           RigidBody3D
var _current_gear:  int   = 0
var _current_pitch: float = 0.85
var _shift_timer:   float = 0.0

# ==============================================================================
# READY
# ==============================================================================

func _ready() -> void:
	_car = get_parent() as RigidBody3D

	_idle.pitch_scale   = idle_pitch
	_engine.pitch_scale = _current_pitch
	_idle.volume_db     = idle_volume_run_db
	_engine.volume_db   = -80.0
	_idle.play()
	_engine.play()

# UPDATE

func _process(delta: float) -> void:
	if not _car:
		return

	var speed_kph = _car.linear_velocity.length() * 3.6
	var throttle  = Input.get_action_strength("accelerate") if not _car.input_blocked else 0.0

	# --- Gear detection ---
	var new_gear = _get_gear(speed_kph)
	if new_gear != _current_gear:
		_current_gear = new_gear
		_shift_timer  = shift_dip_duration

	if _shift_timer > 0.0:
		_shift_timer -= delta

	# --- Pitch ---
	var gear_min  = gear_speeds[_current_gear]
	var gear_max  = gear_speeds[min(_current_gear + 1, gear_speeds.size() - 1)]
	var rpm_ratio = clamp((speed_kph - gear_min) / max(gear_max - gear_min, 1.0), 0.0, 1.0)

	var throttle_pitch_boost = throttle * 0.15
	var target_pitch = lerp(engine_pitch_min, engine_pitch_max, rpm_ratio) + throttle_pitch_boost

	if _shift_timer > 0.0:
		var dip_factor = _shift_timer / shift_dip_duration
		target_pitch  *= lerp(1.0, shift_dip_amount, dip_factor)

	_current_pitch      = lerp(_current_pitch, target_pitch, pitch_blend_speed * delta)
	_engine.pitch_scale = _current_pitch

	# --- Volume ---
	var target_engine_db: float
	var target_idle_db: float

	var is_idle = speed_kph < 5.0 and throttle < 0.05

	if is_idle:
		target_engine_db = -20.0
		target_idle_db   = idle_volume_run_db
	else:
		var blend        = clamp(speed_kph / 20.0, 0.0, 1.0)
		target_engine_db = lerp(-80.0, lerp(engine_volume_idle_db, engine_volume_full_db, throttle), blend)
		target_idle_db   = lerp(idle_volume_run_db, -80.0, blend)

	_engine.volume_db = lerp(_engine.volume_db, target_engine_db, volume_blend_speed * delta)
	_idle.volume_db   = lerp(_idle.volume_db,   target_idle_db,   volume_blend_speed * delta)
	
# HELPERS
func _get_gear(speed_kph: float) -> int:
	for i in range(gear_speeds.size() - 1):
		if speed_kph < gear_speeds[i + 1]:
			return i
	return gear_speeds.size() - 2
