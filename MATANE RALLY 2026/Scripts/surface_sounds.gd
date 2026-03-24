extends Node3D
# ==============================================================================
# SurfaceSound.gd
# ==============================================================================

@export_group("Sounds")
@export var gravel_accel:      AudioStream
@export var gravel_brake:      AudioStream
@export var collision_sounds:  Array[AudioStream]

@export_group("Gravel")
@export var accel_threshold: float  = 0.1
@export var gravel_volume_db: float = -6.0
@export var fade_speed: float       = 6.0

@export_group("Collision")
@export var min_collision_speed: float = 10.0
@export var collision_volume_db: float = 0.0

@export var _accel_player:     AudioStreamPlayer3D
@export var _brake_player:     AudioStreamPlayer3D
@export var _collision_player: AudioStreamPlayer3D

var _car:           RigidBody3D
var _wheels:        Array = []

func _ready() -> void:
	_car = get_parent() as RigidBody3D
	_wheels = _car.get_node("WheelContainer").get_children()

	_accel_player.stream    = gravel_accel
	_brake_player.stream    = gravel_brake
	_accel_player.volume_db = -80.0
	_brake_player.volume_db = -80.0
	_accel_player.play()
	_brake_player.play()

	_car.contact_monitor        = true
	_car.max_contacts_reported  = 4
	_car.body_entered.connect(_on_collision)

func _process(delta: float) -> void:
	if not _car:
		return

	var gravel_count = _count_gravel_wheels()
	var on_gravel    = gravel_count > 0

	var throttle  = Input.get_action_strength("accelerate") if not _car.input_blocked else 0.0
	var brake     = Input.get_action_strength("brake")      if not _car.input_blocked else 0.0
	var handbrake = Input.is_action_pressed("handbrake")    and not _car.input_blocked
	var speed     = _car.linear_velocity.length() * 3.6

	# --- Accel ---
	if on_gravel and throttle > accel_threshold and speed > 5.0:
		if not _accel_player.playing:
			_accel_player.play()
		_accel_player.volume_db = gravel_volume_db
	else:
		_accel_player.volume_db = lerp(_accel_player.volume_db, -80.0, fade_speed * delta)
		if _accel_player.volume_db <= -79.0:
			_accel_player.stop()

	# --- Brake / Handbrake ---
	var braking = brake > 0.05 or handbrake
	if on_gravel and braking and speed > 3.0:
		if not _brake_player.playing:
			_brake_player.play()
		_brake_player.volume_db = gravel_volume_db
	else:
		_brake_player.volume_db = lerp(_brake_player.volume_db, -80.0, fade_speed * delta)
		if _brake_player.volume_db <= -79.0:
			_brake_player.stop()

func _count_gravel_wheels() -> int:
	var count = 0
	for wheel in _wheels:
		if wheel is RayCast3D and wheel.is_colliding():
			var collider = wheel.get_collider()
			if collider and collider.is_in_group("Gravel"):
				count += 1
	return count

func _on_collision(body: Node) -> void:
	if collision_sounds.is_empty():
		return
	var speed = _car.linear_velocity.length() * 3.6
	if speed < min_collision_speed:
		return
	var impact_ratio            = clamp((speed - min_collision_speed) / 80.0, 0.0, 1.0)
	var vol                     = lerp(collision_volume_db - 12.0, collision_volume_db, impact_ratio)
	_collision_player.stream    = collision_sounds[randi() % collision_sounds.size()]
	_collision_player.volume_db = vol
	_collision_player.play()
