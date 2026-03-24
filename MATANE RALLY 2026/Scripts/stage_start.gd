extends Node

@export_group("Setup")
@export var copilot: NodePath
@export var car: NodePath
@export var countdown_duration: float = 6.0

signal car_released
var _timer: float = 0.0
var _released: bool = false
var _frozen: bool = false
var _car_node: RigidBody3D

func _ready() -> void:
	# co-pilot check
	if copilot:
		get_node(copilot).start()
		print("[StageStart] Co-pilot started.")
	else:
		push_warning("[StageStart] No copilot path assigned.")

	#input block and getting car node
	if car:
		_car_node = get_node(car)
		_car_node.input_blocked = true
		print("[StageStart] Waiting for car to settle...")
	else:
		push_warning("[StageStart] No car path assigned.")

func _process(delta: float) -> void:
	if _released:
		return

	# Wait for car to settle before freezing
	if not _frozen and _car_node:
		if _car_node.linear_velocity.length() < 0.1:
			_car_node.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			_car_node.freeze = true
			_frozen = true
			print("[StageStart] Car settled and frozen — releasing in %.0fs." % countdown_duration)

	# Only start countdown once frozen
	if _frozen:
		_timer += delta
		if _timer >= countdown_duration:
			_release_car()

func _release_car() -> void:
	#releases car after 6 seconds
	_released = true
	if _car_node:
		_car_node.freeze = false
		_car_node.input_blocked = false
		emit_signal("car_released")
		print("[StageStart] Car released — go!")
