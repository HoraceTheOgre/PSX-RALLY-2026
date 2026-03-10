extends Camera3D

# ==============================================================================
# CockpitCamera.gd
# Place this Camera3D as a child of your car where you want the eye position.
# top_level = true detaches it from the parent transform so we can stabilize it.
# ==============================================================================

@export var target: RigidBody3D

# --- FOV ---
@export_group("FOV")
@export var base_fov: float = 80.0
@export var max_fov: float  = 90.0
@export var max_speed_kph: float = 100.0
@export var fov_smooth_speed: float = 4.0

# --- Stabilization ---
@export_group("Stabilization")
## How fast the camera catches up to the car's yaw (left/right steering).
## Lower = more lag in corners. 8 is a good default.
@export var rotation_smooth_speed: float = 12
## 0 = horizon never tilts on bumps. 1 = full raw car pitch.
@export var pitch_influence: float = 0.15
## 0 = never rolls in corners. 1 = full car roll.
@export var roll_influence: float = 0.08

# --- Internal ---
var _current_fov: float
var _smoothed_yaw: float   = 0.0
var _smoothed_pitch: float = 0.0
var _smoothed_roll: float  = 0.0
# The offset from the car's origin to where the camera was placed in the editor
var _local_offset: Vector3

func _ready() -> void:
	# Detach from parent transform — this is the key fix
	top_level = true

	_current_fov = base_fov
	fov          = base_fov

	if target:
		# Store where the camera sits relative to the car
		_local_offset = target.global_transform.basis.inverse() * (global_position - target.global_position)
		# Seed the smoothed angles so there's no snap on first frame
		_read_car_angles(target.global_transform.basis,
			_smoothed_yaw, _smoothed_pitch, _smoothed_roll)

func _physics_process(delta: float) -> void:
	if not target:
		return

	var speed_kph   = target.linear_velocity.length() * 3.6
	var speed_ratio = clamp(speed_kph / max_speed_kph, 0.0, 1.0)

	_update_fov(delta, speed_ratio)
	_update_transform(delta)

# ==============================================================================
# FOV
# ==============================================================================

func _update_fov(delta: float, speed_ratio: float) -> void:
	var target_fov = lerp(base_fov, max_fov, speed_ratio * speed_ratio)
	_current_fov   = lerp(_current_fov, target_fov, fov_smooth_speed * delta)
	fov            = _current_fov

# ==============================================================================
# POSITION + STABILIZED ROTATION
# ==============================================================================

func _update_transform(delta: float) -> void:
	var car_basis = target.global_transform.basis

	# --- Extract raw car angles ---
	var raw_yaw   = atan2(-car_basis.z.x, -car_basis.z.z)
	var raw_pitch = asin(clamp(car_basis.z.y, -1.0, 1.0))
	var raw_roll  = atan2(car_basis.x.y, car_basis.y.y)

	# --- Smooth each axis independently ---
	var t = rotation_smooth_speed * delta

	_smoothed_yaw   = lerp_angle(_smoothed_yaw,   raw_yaw + PI,                  t)
	_smoothed_pitch = lerp_angle(_smoothed_pitch,  raw_pitch * pitch_influence,   t)
	_smoothed_roll  = lerp_angle(_smoothed_roll,   raw_roll  * roll_influence,    t)

	# --- Rebuild a stabilized basis from the smoothed angles ---
	var stabilized = Basis.IDENTITY
	stabilized = stabilized.rotated(Vector3.UP,      _smoothed_yaw)
	stabilized = stabilized.rotated(Vector3.RIGHT,   _smoothed_pitch)
	stabilized = stabilized.rotated(Vector3.FORWARD, _smoothed_roll)

	# --- Position: follow the car exactly, no smoothing on position ---
	var world_pos = target.global_position + car_basis * _local_offset

	global_transform = Transform3D(stabilized, world_pos)

# ==============================================================================
# HELPERS
# ==============================================================================

func _read_car_angles(basis: Basis, out_yaw: float, out_pitch: float, out_roll: float) -> void:
	_smoothed_yaw   = atan2(-basis.z.x, -basis.z.z)
	_smoothed_pitch = asin(clamp(basis.z.y, -1.0, 1.0)) * pitch_influence
	_smoothed_roll  = atan2(basis.x.y, basis.y.y) * roll_influence
