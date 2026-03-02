extends Camera3D

# --- SETUP ---
@export var target: Node3D        # Drag your Car node here in Inspector
@export var offset: Vector3 = Vector3(0, 3.0, 5.0) # Up 3m, Back 6m
@export var smooth_speed: float = 10.0 # Higher = Snappier, Lower = Lazier

# --- SPEED FEEL ---
@export_group("Speed Effects")
@export var enable_speed_effects: bool = true
@export var max_speed_kph: float = 180.0           # Speed where effects are maxed

# Camera pulls back at high speed
@export var speed_zoom_out: float = 2.0            # Extra distance at max speed
@export var zoom_smooth_speed: float = 5.0

# FOV increases at high speed (tunnel vision effect)
@export var base_fov: float = 75.0
@export var max_fov: float = 90.0                  # FOV at max speed
@export var fov_smooth_speed: float = 4.0

# Camera drops lower at high speed (more dramatic angle)
@export var speed_height_drop: float = 1.0         # How much lower at max speed
@export var height_smooth_speed: float = 3.0

# Camera lags behind more at high speed (feels like you're pulling ahead)
@export var speed_lag_multiplier: float = 0.5      # Extra lag at max speed

# --- SHAKE ---
@export_group("Camera Shake")
@export var enable_shake: bool = false
@export var shake_intensity: float = 0.05          # Max shake amount
@export var shake_speed: float = 30.0              # How fast the shake oscillates

# --- LOOK AHEAD ---
@export_group("Look Ahead")
@export var look_ahead_amount: float = 5.0         # How far ahead to look when moving fast
@export var look_ahead_smooth: float = 3.0

# --- Internal State ---
var current_extra_distance: float = 0.0
var current_height_offset: float = 0.0
var current_fov: float = 75.0
var current_look_ahead: Vector3 = Vector3.ZERO
var shake_offset: Vector3 = Vector3.ZERO
var shake_time: float = 0.0

func _ready():
	current_fov = base_fov
	fov = base_fov

func _physics_process(delta):
	if !target: return
	
	# Get car speed
	var velocity = Vector3.ZERO
	if target is RigidBody3D:
		velocity = target.linear_velocity
	
	var speed_ms = velocity.length()
	var speed_kph = speed_ms * 3.6
	var speed_ratio = clamp(speed_kph / max_speed_kph, 0.0, 1.0)
	
	if enable_speed_effects:
		apply_speed_effects(delta, speed_ratio, velocity)
	
	if enable_shake:
		apply_shake(delta, speed_ratio)
	
	# 1. CALCULATE TARGET POSITION WITH SPEED EFFECTS
	var dynamic_offset = offset
	dynamic_offset.z += current_extra_distance          # Pull back at speed
	dynamic_offset.y -= current_height_offset           # Drop lower at speed
	
	var target_pos = target.global_position + (target.global_transform.basis * dynamic_offset)
	
	# 2. SMOOTHLY MOVE THERE (slower smoothing at high speed = more lag)
	var effective_smooth = smooth_speed * (1.0 - (speed_ratio * speed_lag_multiplier))
	effective_smooth = max(effective_smooth, 2.0)  # Don't go too slow
	
	global_position = global_position.lerp(target_pos, effective_smooth * delta)
	
	# Add shake
	global_position += shake_offset
	
	# 3. LOOK AT THE CAR (with look-ahead at speed)
	var look_target = target.global_position + Vector3(0, 1.0, 0)
	look_target += current_look_ahead
	look_at(look_target, Vector3.UP)
	
	# 4. APPLY FOV
	fov = current_fov

func apply_speed_effects(delta: float, speed_ratio: float, velocity: Vector3):
	# Smooth zoom out
	var target_extra_distance = speed_ratio * speed_ratio * speed_zoom_out  # Quadratic for more effect at high speed
	current_extra_distance = lerp(current_extra_distance, target_extra_distance, zoom_smooth_speed * delta)
	
	# Smooth height drop
	var target_height_drop = speed_ratio * speed_height_drop
	current_height_offset = lerp(current_height_offset, target_height_drop, height_smooth_speed * delta)
	
	# Smooth FOV change
	var target_fov = lerp(base_fov, max_fov, speed_ratio * speed_ratio)
	current_fov = lerp(current_fov, target_fov, fov_smooth_speed * delta)
	
	# Look ahead in velocity direction
	var target_look_ahead = Vector3.ZERO
	if velocity.length() > 1.0:
		var velocity_flat = velocity
		velocity_flat.y = 0
		target_look_ahead = velocity_flat.normalized() * look_ahead_amount * speed_ratio
	current_look_ahead = current_look_ahead.lerp(target_look_ahead, look_ahead_smooth * delta)

func apply_shake(delta: float, speed_ratio: float):
	shake_time += delta * shake_speed
	
	# Only shake at higher speeds
	var shake_amount = speed_ratio * speed_ratio * shake_intensity
	
	if shake_amount > 0.001:
		shake_offset = Vector3(
			sin(shake_time * 1.1) * shake_amount,
			sin(shake_time * 1.3) * shake_amount * 0.5,
			sin(shake_time * 0.9) * shake_amount * 0.3
		)
	else:
		shake_offset = Vector3.ZERO
