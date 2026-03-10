extends Node

# ==============================================================================
# StageStart.gd
# - Starts the co-pilot immediately on scene load
# - Disables the car's physics processing for 6 seconds so it can't move
# Attach to any Node in your stage scene.
# ==============================================================================

@export_group("Setup")
## Path to your CoPilot node
@export var copilot: NodePath
## Path to your car RigidBody3D
@export var car: NodePath
## How long to freeze the car before the player can drive (seconds)
@export var countdown_duration: float = 6.0

var _timer: float = 0.0
var _released: bool = false
var _car_node: RigidBody3D

# ==============================================================================
# READY — co-pilot starts immediately, car is frozen
# ==============================================================================

func _ready() -> void:
	# Start co-pilot right away
	if copilot:
		get_node(copilot).start()
		print("[StageStart] Co-pilot started.")
	else:
		push_warning("[StageStart] No copilot path assigned.")

	# Freeze the car so it can't move or accept input
	if car:
		_car_node = get_node(car)
		_car_node.set_physics_process(false)
		# Also lock it in place so gravity doesn't move it during the freeze
		_car_node.freeze = true
		print("[StageStart] Car frozen — releasing in %.0fs." % countdown_duration)
	else:
		push_warning("[StageStart] No car path assigned.")

# ==============================================================================
# COUNTDOWN
# ==============================================================================

func _process(delta: float) -> void:
	if _released:
		return

	_timer += delta

	if _timer >= countdown_duration:
		_release_car()

func _release_car() -> void:
	_released = true

	if _car_node:
		_car_node.freeze = false
		_car_node.set_physics_process(true)
		print("[StageStart] Car released — go!")
