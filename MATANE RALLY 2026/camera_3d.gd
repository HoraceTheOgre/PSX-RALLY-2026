extends Camera3D

# --- SETUP ---
@export var target: Node3D        # Drag your Car node here in Inspector
@export var offset: Vector3 = Vector3(0, 3.0, 6.0) # Up 3m, Back 6m
@export var smooth_speed: float = 10.0 # Higher = Snappier, Lower = Lazier

func _physics_process(delta):
	if !target: return
	
	# 1. CALCULATE TARGET POSITION
	# We take the car's position and add the offset relative to its rotation.
	# This means if the car turns, the camera swings around to stay behind it.
	var target_pos = target.global_position + (target.global_transform.basis * offset)
	
	# 2. SMOOTHLY MOVE THERE
	# We use linear interpolation (lerp) to slide the camera towards the target position.
	global_position = global_position.lerp(target_pos, smooth_speed * delta)
	
	# 3. LOOK AT THE CAR
	# We look slightly above the car's center (Vector3(0, 1.0, 0)) so the car isn't perfectly center screen.
	var look_target = target.global_position + Vector3(0, 1.0, 0)
	look_at(look_target, Vector3.UP)
