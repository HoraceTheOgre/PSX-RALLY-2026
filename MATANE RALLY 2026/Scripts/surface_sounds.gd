extends Node3D
# ==============================================================================
# SurfaceSound.gd
# ==============================================================================

@export_group("Sounds")
@export var gravel_accel: AudioStream
@export var gravel_brake: AudioStream
@export var collision_sounds: Array[AudioStream]

@export_group("Gravel")
@export var accel_threshold: float  = 0.3
@export var brake_threshold: float  = 0.3
@export var gravel_volume_db: float = -6.0
@export var fade_speed: float       = 6.0

@export_group("Collision")
@export var min_collision_speed: float = 10.0
@export var collision_volume_db: float = 0.0

@export var _accel_player:     AudioStreamPlayer3D
@export var _brake_player:     AudioStreamPlayer3D
@export var _collision_player: AudioStreamPlayer3D

var _car: RigidBody3D

func _ready() -> void:
	_car = get_parent() as RigidBody3D

	_accel_player.stream    = gravel_accel
	_brake_player.stream    = gravel_brake
	_accel_player.volume_db = -80.0
	_brake_player.volume_db = -80.0
	_accel_player.play()
	_brake_player.play()

	# Required for body_entered to fire
	_car.contact_monitor     = true
	_car.max_contacts_reported = 4
	_car.body_entered.connect(_on_collision)

func _process(delta: float) -> void:
	if not _car:
		return

	var on_gravel = _is_on_gravel()
	#get input if not block for stage start, if input blocked well you aint moving foo
	var throttle  = Input.get_action_strength("accelerate") if not _car.input_blocked else 0.0
	var brake     = Input.get_action_strength("brake")      if not _car.input_blocked else 0.0
	var handbrake = Input.is_action_pressed("handbrake")    and not _car.input_blocked
	var speed     = _car.linear_velocity.length() * 3.6

	# Acceleration gravel noises
	var target_accel_db: float
	if on_gravel and throttle > accel_threshold and speed > 5.0:
		target_accel_db = gravel_volume_db
	else:
		target_accel_db = -80.0
	_accel_player.volume_db = lerp(_accel_player.volume_db, target_accel_db, fade_speed * delta)

	#braking gravel sounds
	# Triggers on brake or handbrake, fades out below 3 km/h
	var target_brake_db: float
	var braking = brake > brake_threshold or handbrake
	if on_gravel and braking and speed > 3.0:
		_brake_player.volume_db = gravel_volume_db 
		#fading the sound
	else:
		_brake_player.volume_db = lerp(_brake_player.volume_db, -80.0, fade_speed * delta)  # smooth fade out

func _is_on_gravel() -> bool:
	#check the surface the car is on
	var wheels = _car.get_node("WheelContainer").get_children()
	for wheel in wheels:
		if wheel is RayCast3D and wheel.is_colliding():
			var collider = wheel.get_collider()
			if collider and collider.is_in_group("Gravel"):
				return true
	return false

func _on_collision(body: Node) -> void:
	#check collision for when to play collision sounds
	if collision_sounds.is_empty():
		return
	var speed = _car.linear_velocity.length() * 3.6
	if speed < min_collision_speed:
		return
	var impact_ratio        = clamp((speed - min_collision_speed) / 80.0, 0.0, 1.0)
	var vol                 = lerp(collision_volume_db - 12.0, collision_volume_db, impact_ratio)
	_collision_player.stream    = collision_sounds[randi() % collision_sounds.size()]
	_collision_player.volume_db = vol
	_collision_player.play()
