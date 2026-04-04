extends Node

@export_group("Setup")
@export var copilot: NodePath
@export var car: NodePath
@export var countdown_duration: float = 6.0

signal waiting_for_handbrake
signal countdown_started
signal car_released

var _timer: float = 0.0
var _released: bool = false
var _frozen: bool = false
var _countdown_active: bool = false
var _car_node: RigidBody3D

func _ready() -> void:
	if copilot:
		get_node(copilot).start()
		print("[StageStart] Co-pilot started.")
	else:
		push_warning("[StageStart] No copilot path assigned.")

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
			emit_signal("waiting_for_handbrake")
			print("[StageStart] Car settled. Waiting for handbrake.")

	# Wait for player handbrake input to start the countdown
	if _frozen and not _released:
		if not _countdown_active:
			if Input.is_action_pressed("handbrake"):
				_countdown_active = true
				emit_signal("countdown_started")
				if copilot:
					get_node(copilot).activate_triggers()
				print("[StageStart] Handbrake pulled. Countdown started!")
		else:
			_timer += delta
			if _timer >= countdown_duration:
				_release_car()

func _release_car() -> void:
	_released = true
	if _car_node:
		_car_node.freeze = false
		_car_node.input_blocked = false
		emit_signal("car_released")
		print("[StageStart] Car released — go!")
