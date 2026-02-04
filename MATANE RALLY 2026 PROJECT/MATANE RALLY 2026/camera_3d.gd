extends Camera3D

# --- TARGETING ---
@export var target: Node3D        
@export var offset: Vector3 = Vector3(-1, 3.5, 7.0) # Lowered Y slightly for speed

# --- SENSATION OF SPEED ---
@export_group("Speed Effects")
@export var min_fov: float = 75.0      
@export var max_fov: float = 115.0     # Higher FOV = More speed sensation
@export var lag_speed: float = 10.0    # Increased! (10 = Snappy, 4 = Loose)
@export var shake_power: float = 0.05  

# --- INTERNAL ---
var current_shake: Vector3 = Vector3.ZERO

func _physics_process(delta):
	if !target: return
	
	# 1. CALCULATE SPEED
	var car_speed = target.linear_velocity.length() * 3.6
	var speed_percent = clamp(car_speed / 200.0, 0.0, 1.0) 
	
	# 2. DYNAMIC FOV (The Warp Effect)
	var target_fov = lerp(min_fov, max_fov, speed_percent)
	fov = lerp(fov, target_fov, 5.0 * delta) # Reacts faster now
	
	# 3. DYNAMIC OFFSET (Subtle Pull Back)
	var speed_offset = offset
	# ONLY move back 0.5 meters at top speed (Prevents "Floating away")
	speed_offset.z += speed_percent * 0.5  
	
	# 4. FOLLOW LOGIC
	var target_pos = target.global_position + (target.global_transform.basis * speed_offset)
	
	# 5. RUMBLE
	if car_speed > 50.0:
		current_shake.x = randf_range(-1.0, 1.0) * shake_power * speed_percent
		current_shake.y = randf_range(-1.0, 1.0) * shake_power * speed_percent
	else:
		current_shake = Vector3.ZERO
		
	# Apply position (With high lag_speed, this snaps to position faster)
	global_position = global_position.lerp(target_pos + current_shake, lag_speed * delta)
	
	# 6. LOOK AT
	# Look slightly above the car so you see the road ahead
	var look_target = target.global_position + Vector3(0, 0.0, 0)
	look_at(look_target)
