extends RigidBody3D

# -----------------------------------------------------------------------------
# CONFIGURATION GROUPS (Tuned for 20kg Mass)
# -----------------------------------------------------------------------------

@export_group("Suspension")
@export var spring_stiffness: float = 180.0 # Tuned for 20kg (Not 15000!)
@export var spring_damping_ratio: float = 1.0 # High damping to stop bouncing
@export var suspension_rest_length: float = 1 
@export var wheel_radius: float = 0.33 

@export_group("Visual Wheels")
@export var mesh_fl: MeshInstance3D
@export var mesh_fr: MeshInstance3D
@export var mesh_rl: MeshInstance3D
@export var mesh_rr: MeshInstance3D

@export_group("Engine & Transmission")
@export var engine_power: float = 120.0 # Increased slightly for 20kg agility
@export var max_speed: float = 40.0 
@export var power_curve: Curve # Optional: Define torque vs speed

@export_group("Steering & Handling")
@export var steer_angle: float = 30.0 
@export var steer_speed: float = 5.0 # Snappier steering for arcade feel
@export var anti_roll_force: float = 15.0 # Tuned for 20kg

@export_group("Surface Physics")
@export var grip_tarmac: float = 2.5 # Higher grip = tighter turns
@export var grip_dirt: float = 1.0   # Lower grip = drifting
@export var drag_tarmac: float = 0.02
@export var drag_dirt: float = 0.1

@export_group("Assists")
@export var downforce_strength: float = 0.5 # Keeps you on the floor at high speed
@export var air_control_strength: float = 20.0 # Rotate in mid-air

# -----------------------------------------------------------------------------
# INTERNAL STATE
# -----------------------------------------------------------------------------

@onready var wheels = {
	"FL": $WheelContainer/FL,
	"FR": $WheelContainer/FR,
	"RL": $WheelContainer/RL,
	"RR": $WheelContainer/RR
}

var prev_compression = { "FL": 0.0, "FR": 0.0, "RL": 0.0, "RR": 0.0 }
var current_steer_angle: float = 0.0
var speed_ratio: float = 0.0 

func _ready():
	# Fix for Godot 4 RigidBody Center of Mass
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.2, 0) # Low CoM prevents flipping
	
	for ray in wheels.values():
		ray.target_position = Vector3(0, -suspension_rest_length, 0)
		ray.enabled = true

func _process(_delta):
	# Update Visuals in _process for smooth frame rate
	update_wheel_visual(mesh_fl, "FL")
	update_wheel_visual(mesh_fr, "FR")
	update_wheel_visual(mesh_rl, "RL")
	update_wheel_visual(mesh_rr, "RR")

func _physics_process(delta):
	# 1. Inputs
	var throttle = Input.get_axis("brake", "accelerate")
	var steer_input = Input.get_axis("steer_right", "steer_left")
	var pitch_input = Input.get_axis("accelerate", "brake") # For air control
	
	# 2. Smooth Steering
	current_steer_angle = lerp(current_steer_angle, steer_input * steer_angle, steer_speed * delta)
	
	# 3. Calculate Speed Ratio (for Torque Curve)
	var speed = linear_velocity.length()
	speed_ratio = clamp(speed / max_speed, 0.0, 1.0)
	
	# 4. Physics Loop
	var ground_contact_count = 0
	
	for w_name in wheels:
		var ray: RayCast3D = wheels[w_name]
		if ray.is_colliding():
			ground_contact_count += 1
			process_ground_physics(w_name, ray, throttle, delta)
		else:
			prev_compression[w_name] = 0.0
	
	# 5. Air Control (Only works when flying)
	if ground_contact_count == 0:
		apply_air_control(steer_input, pitch_input, delta)
	
	# 6. Anti-Roll Bars (Prevents body roll in corners)
	apply_anti_roll(wheels["FL"], wheels["FR"])
	apply_anti_roll(wheels["RL"], wheels["RR"])
	
	# 7. Downforce (Aerodynamics)
	if ground_contact_count > 0:
		apply_central_force(-transform.basis.y * speed * downforce_strength)

# -----------------------------------------------------------------------------
# PHYSICS SOLVER
# -----------------------------------------------------------------------------

func process_ground_physics(w_name: String, ray: RayCast3D, throttle: float, delta: float):
	var collision_point = ray.get_collision_point()
	var collider = ray.get_collider()
	
	# --- A. SUSPENSION ---
	var distance = ray.global_position.distance_to(collision_point)
	var compression = suspension_rest_length - distance
	if compression < 0: compression = 0
	
	var spring_force = compression * spring_stiffness
	var suspension_velocity = (compression - prev_compression[w_name]) / delta
	prev_compression[w_name] = compression
	
	var wheel_load = mass / 4.0
	var damping_coef = 2.0 * spring_damping_ratio * sqrt(spring_stiffness * wheel_load)
	var damp_force = suspension_velocity * damping_coef
	
	var final_susp_force = clamp(spring_force + damp_force, 0, 5000)
	apply_force(ray.global_transform.basis.y * final_susp_force, collision_point - global_position)
	
	# --- B. SURFACE DETECTION ---
	var current_grip = grip_tarmac
	var current_drag = drag_tarmac
	
	if collider.is_in_group("surface_dirt"):
		current_grip = grip_dirt
		current_drag = drag_dirt
	
	# --- C. FRICTION (DRIFT LOGIC) ---
	var wheel_basis = global_transform.basis
	
	if w_name in ["FL", "FR"]:
		wheel_basis = wheel_basis.rotated(global_transform.basis.y, deg_to_rad(current_steer_angle))
		
	var forward_dir = -wheel_basis.z # <--- Now used for Engine
	var right_dir = wheel_basis.x
	
	# 1. Lateral Velocity
	var tire_vel = linear_velocity + angular_velocity.cross(collision_point - global_position)
	var lat_vel = tire_vel.dot(right_dir)
	
	# 2. Desired Friction (Infinite Grip)
	var desired_friction = -lat_vel * (mass / 4.0) / delta
	
	# 3. Max Limit (Drift Threshold)
	var max_tire_force = (mass / 4.0) * 20.0 * current_grip 
	
	# Make Rear Wheels Slippery for Drifting
	if w_name in ["RL", "RR"]:
		max_tire_force *= 0.5 
	
	# 4. Clamp Force
	var actual_friction = clamp(desired_friction, -max_tire_force, max_tire_force)
	apply_force(right_dir * actual_friction, collision_point - global_position)
	
	# --- D. PROPULSION (AWD RALLY MODE) ---
	# We want power on ALL wheels, but more on the back so we can still drift.
	
	var awd_bias = 0.0
	
	if w_name in ["RL", "RR"]:
		awd_bias = 0.5  # 70% Power to Rear (Keeps it drifty)
	elif w_name in ["FL", "FR"]:
		awd_bias = 0.5 # 30% Power to Front (Helps climb hills/pull out of slides)
	
	# Only apply force if this wheel is supposed to have power
	if awd_bias > 0.0:
		var torque_mult = 1.0
		if power_curve:
			torque_mult = power_curve.sample(speed_ratio)
			
		# Multiply by 'awd_bias' so we don't accidentally double our total power
		var drive_force = forward_dir * throttle * engine_power * torque_mult * awd_bias
		apply_force(drive_force, collision_point - global_position)
	apply_force(-tire_vel * current_drag, collision_point - global_position)

# -----------------------------------------------------------------------------
# HELPER SYSTEMS
# -----------------------------------------------------------------------------

func update_wheel_visual(mesh: MeshInstance3D, w_name: String):
	if !mesh: return
	var ray = wheels[w_name]
	
	if ray.is_colliding():
		# Visual fix: ensure wheel sits ON ground, not under it
		var hit_point = ray.get_collision_point()
		mesh.global_position = hit_point + (ray.global_transform.basis.y * wheel_radius)
	else:
		# Smooth drop in air
		var target_y = -suspension_rest_length + wheel_radius
		mesh.position.y = lerp(mesh.position.y, target_y, 0.2)

	if w_name in ["FL", "FR"]:
		mesh.rotation.y = deg_to_rad(current_steer_angle)

func apply_anti_roll(wheel_L, wheel_R):
	var travel_L = 0.0
	var travel_R = 0.0
	
	if wheel_L.is_colliding():
		var dist = wheel_L.global_position.distance_to(wheel_L.get_collision_point())
		travel_L = suspension_rest_length - dist
		
	if wheel_R.is_colliding():
		var dist = wheel_R.global_position.distance_to(wheel_R.get_collision_point())
		travel_R = suspension_rest_length - dist
		
	var roll_force = (travel_L - travel_R) * anti_roll_force
	
	if wheel_L.is_colliding():
		apply_force(Vector3.DOWN * roll_force, wheel_L.position - global_position)
	if wheel_R.is_colliding():
		apply_force(Vector3.UP * roll_force, wheel_R.position - global_position)

func apply_air_control(steer, pitch, delta):
	var rot_force = air_control_strength * delta * 50.0
	# Yaw (Steer in air)
	apply_torque(transform.basis.y * steer * -rot_force)
	# Pitch (Flip control)
	apply_torque(transform.basis.x * pitch * rot_force)
