extends Node

@export_group("Setup")
@export var car:       RigidBody3D
@export var slow_zone: Area3D
@export var stop_zone: Area3D

@export_group("Slow Zone")
## Speed the car is capped at inside the slow zone (km/h)
@export var slow_zone_target_kph: float = 40.0
## How quickly the car brakes down to the target speed
@export var slow_zone_brake_force: float = 18000.0

@export_group("Stop Zone")
## How quickly the car brakes to a full stop
@export var stop_zone_brake_force: float = 28000.0
## Speed threshold at which we consider the car fully stopped (km/h)
@export var stop_threshold_kph: float = 0.5

# ==============================================================================
# INTERNAL
# ==============================================================================

enum State { NONE, SLOWING, STOPPING, STOPPED }
var _state: State = State.NONE

# ==============================================================================
# READY
# ==============================================================================

func _ready() -> void:
	#defining zones
	if slow_zone:
		slow_zone.body_entered.connect(_on_slow_zone_entered)
	else:
		push_warning("[StageEnd] No slow zone assigned.")

	if stop_zone:
		stop_zone.body_entered.connect(_on_stop_zone_entered)
	else:
		push_warning("[StageEnd] No stop zone assigned.")

func reset() -> void:
	_state = State.NONE
	if car:
		car.input_blocked = false
	if slow_zone:
		slow_zone.monitoring = false
		slow_zone.monitoring = true
	if stop_zone:
		stop_zone.monitoring = false
		stop_zone.monitoring = true
	print("[StageEnd] Reset — ready for next run.")
# ==============================================================================
# PHYSICS
# ==============================================================================

func _physics_process(delta: float) -> void:
	#if nothing it not work
	if not car or _state == State.NONE or _state == State.STOPPED:
		return

	var speed_kph = car.linear_velocity.length() * 3.6

		#slowing the car
	if _state == State.SLOWING:
		if speed_kph > slow_zone_target_kph:
			# Apply braking force opposite to velocity
			var brake_dir = -car.linear_velocity.normalized()
			car.apply_central_force(brake_dir * slow_zone_brake_force)
		else:
			# Cap speed — strip any excess velocity above the limit
			var capped = car.linear_velocity.normalized() * (slow_zone_target_kph / 3.6)
			car.linear_velocity = capped

		#stopping the car
	elif _state == State.STOPPING:
		if speed_kph > stop_threshold_kph:
			var brake_dir = -car.linear_velocity.normalized()
			car.apply_central_force(brake_dir * stop_zone_brake_force)
		else:
			# Fully stop and block input
			car.linear_velocity  = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			car.input_blocked    = true
			_state = State.STOPPED
			print("[StageEnd] Stage complete!")

# ==============================================================================
# ZONE SIGNALS
# ==============================================================================

func _on_slow_zone_entered(body: Node) -> void:
	#changement de state
	if body != car:
		return
	if _state == State.NONE:
		_state = State.SLOWING
		print("[StageEnd] Slow zone entered — reducing speed to %.0f km/h." % slow_zone_target_kph)

func _on_stop_zone_entered(body: Node) -> void:
	#changement de state
	if body != car:
		return
	if _state != State.STOPPED:
		_state = State.STOPPING
		print("[StageEnd] Stop zone entered — bringing car to a halt.")
