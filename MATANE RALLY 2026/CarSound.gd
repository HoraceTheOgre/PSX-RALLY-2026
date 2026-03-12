extends AudioStreamPlayer3D

# ==============================================================================
# CarSound.gd
# Attach to an AudioStreamPlayer3D inside your car.
# Assign a looping engine WAV/OGG to the stream in the Inspector.
# ==============================================================================

@export var car: RigidBody3D

@export_group("Pitch")
## Pitch when the car is idle (engine just running, no throttle)
@export var idle_pitch: float = 0.6
## Pitch at full throttle + max speed
@export var max_pitch: float  = 2.2
## Max speed used to calculate pitch from speed (kph)
@export var max_speed_kph: float = 180.0
## How quickly pitch responds to throttle/speed changes
@export var pitch_smooth_speed: float = 6.0

@export_group("Volume")
## Volume at idle (dB)
@export var idle_volume_db: float = -6.0
## Volume at full throttle
@export var max_volume_db: float  = 0.0

var _current_pitch: float

func _ready() -> void:
	_current_pitch = idle_pitch
	pitch_scale    = idle_pitch
	volume_db      = idle_volume_db
	play()

func _physics_process(delta: float) -> void:
	if not car:
		return

	var throttle    = Input.get_action_strength("accelerate")
	var speed_kph   = car.linear_velocity.length() * 3.6
	var speed_ratio = clamp(speed_kph / max_speed_kph, 0.0, 1.0)

	# Pitch is driven by whichever is higher — throttle input or current speed.
	# This means the pitch drops when you lift off but not instantly.
	var throttle_pitch = lerp(idle_pitch, max_pitch, throttle)
	var speed_pitch    = lerp(idle_pitch, max_pitch, speed_ratio)
	var target_pitch   = max(throttle_pitch, speed_pitch)

	_current_pitch = lerp(_current_pitch, target_pitch, pitch_smooth_speed * delta)
	pitch_scale    = _current_pitch

	# Volume follows throttle
	volume_db = lerp(idle_volume_db, max_volume_db, throttle)
