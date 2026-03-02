extends RigidBody3D

# ==============================================================================
# RALLY CONTROLLER - CLEAN VERSION WITH DEBUG
# ==============================================================================

@export_group("Suspension System - Gravel")
@export var spring_stiffness_gravel: float = 100000.0
@export var spring_progressive_rate_gravel: float = 2.0
@export var damping_compression_gravel: float = 20000.0
@export var damping_rebound_gravel: float = 18000.0
@export var rest_length_gravel: float = 0.65
@export var max_compression_gravel: float = 0.5
@export var bump_stop_stiffness_gravel: float = 100000.0
@export var arb_stiffness_front_gravel: float = 12000.0  # CHANGED: 8000 → 12000
@export var arb_stiffness_rear_gravel: float = 18000.0   # CHANGED: 10000 → 15000

@export_group("Suspension System - Tarmac")
@export var spring_stiffness_tarmac: float = 110000.0    
@export var spring_progressive_rate_tarmac: float = 1.5  
@export var damping_compression_tarmac: float = 22000.0 
@export var damping_rebound_tarmac: float = 20000.0     
@export var rest_length_tarmac: float = 0.65            
@export var max_compression_tarmac: float = 0.5        
@export var bump_stop_stiffness_tarmac: float = 140000.0  
@export var arb_stiffness_front_tarmac: float = 20000.0  
@export var arb_stiffness_rear_tarmac: float = 22000.0 
# --- Configuration: Suspension Blending ---
@export_group("Suspension Adaptation")
@export var suspension_blend_speed: float = 2.0
@export var wheel_radius: float = 0.3
@export var max_suspension_force: float = 50000.0

# --- Configuration: Anti-Pitch ---
@export_group("Anti-Pitch Control")
@export var enable_anti_pitch: bool = true
@export var anti_pitch_strength: float = 80000.0
@export var pitch_damping_strength: float = 40000.0

@export_group("Drivetrain")
@export var engine_power: float = 20000.0
@export var power_curve_falloff: float = 0.05
@export var top_speed_kph: float = 220.0
@export var torque_split: float = 0.5  # High-speed default
@export var min_power_ratio: float = 0.85

@export_subgroup("Dynamic Torque Split")
@export var enable_dynamic_torque: bool = true
@export var low_speed_rear_split: float = 0.35  
@export var high_speed_rear_split: float = 0.60  
@export var torque_transition_speed_kph: float = 60.0  
# --- Configuration: Surface-Specific Torque ---
@export_group("Surface Torque Multipliers")
@export var gravel_torque_multiplier: float = 1.5
@export var tarmac_torque_multiplier: float = 1

# --- Configuration: Braking & Resistance ---
@export_group("Braking & Resistance")
@export var brake_force: float = 8000.0
@export var handbrake_force: float = 40000.0
@export var rolling_resistance: float = 15.0
@export var air_resistance: float = 0.2

# --- Configuration: Steering ---
@export_group("Steering")
@export var max_steer_angle: float = 0.55
@export var steer_speed: float = 1

@export_subgroup("Low-Speed Steering")
@export var low_speed_steer_reduction_enabled: bool = true
@export var low_speed_min_kph: float = 10.0
@export var low_speed_max_kph: float = 40.0      
@export var min_low_speed_steer_ratio: float = 0.5  

@export_subgroup("High-Speed Steering")
@export var high_speed_reduction_start_kph: float = 60.0  
@export var high_speed_reduction_end_kph: float = 140.0    
@export var min_high_speed_steer_ratio: float = 0.35      
@export var reduce_lateral_grip_with_speed: bool = true

# --- Configuration: Traction ---
@export_group("Traction Circle Override")
@export var longitudinal_grip_multiplier: float = 4.0
@export var straight_line_slip_angle: float = 0.15

# --- Configuration: Debug ---
@export_group("Debug Settings")
@export var enable_detailed_debug: bool = true
@export var debug_interval: float = 0.5  # NEW: Only print every 0.5 seconds
@export var debug_min_speed: float = 20.0
@export var debug_max_speed: float = 100.0
@export var debug_throttle_threshold: float = 0.5

# --- Configuration: Visuals ---
@export_group("Visuals")
@export var mesh_fl: Node3D
@export var mesh_fr: Node3D
@export var mesh_rl: Node3D
@export var mesh_rr: Node3D
@export var spin_axis: Vector3 = Vector3.UP

# --- Internal State ---
@onready var wheels: Array = [
	$WheelContainer/FL, 
	$WheelContainer/FR, 
	$WheelContainer/RL, 
	$WheelContainer/RR
]

var prev_compression: Array[float] = [0.0, 0.0, 0.0, 0.0]
var prev_length: Array[float] = [0.6, 0.6, 0.6, 0.6]
var current_steer_angle: float = 0.0
var initial_transforms: Array[Transform3D]
var accumulated_spin: Array[float] = [0.0, 0.0, 0.0, 0.0]

# Surface detection per wheel
var wheel_surfaces: Array[String] = ["Tarmac", "Tarmac", "Tarmac", "Tarmac"]
# Add at the top with other state variables (around line 95):
var prev_wheel_surfaces: Array[String] = ["Tarmac", "Tarmac", "Tarmac", "Tarmac"]
var suspension_blend: Array[float] = [0.0, 0.0, 0.0, 0.0]
var straight_accel_timer: float = 0.0

# Debug data
var total_drive_force: float = 0.0
var total_lat_force: float = 0.0
var is_handbrake_active: bool = false
var wheel_slip_angles: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_normal_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_drive_forces: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_lateral_forces: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_traction_limits: Array[float] = [0.0, 0.0, 0.0, 0.0]
var body_slip_angle: float = 0.0
var yaw_rate: float = 0.0
var debug_timer: float = 0.0

var prev_steer_angle_for_rate: float = 0.0

func _ready():
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	
	center_of_mass = Vector3(0.0, -0.45,  -0.25) 
	
	wheels[1].position.x = -wheels[0].position.x
	wheels[3].position.x = -wheels[2].position.x
	wheels[1].position.z = wheels[0].position.z
	wheels[3].position.z = wheels[2].position.z
	
	
	var mesh_list = [mesh_fl, mesh_fr, mesh_rl, mesh_rr]
	for mesh in mesh_list:
		if mesh:
			initial_transforms.append(mesh.transform)
		else:
			initial_transforms.append(Transform3D())


# ==============================================================================
# PHYSICS LOOP
# ==============================================================================

func _physics_process(delta: float):
	var throttle = Input.get_action_strength("accelerate")
	var brake = Input.get_action_strength("brake")
	var steer_input = Input.get_axis("steer_right", "steer_left")
	is_handbrake_active = Input.is_action_pressed("handbrake")
	
		# Reverse: when stopped and pressing brake (not throttle), drive backward
	var speed_kph = linear_velocity.length() * 3.6
	var forward_dot = linear_velocity.dot(-global_transform.basis.z)  # Positive = forward
	var is_reversing = false
	
	if brake > 0.1 and throttle < 0.1:
		# Activate reverse if: nearly stopped, OR already moving backward
		if speed_kph < 5.0 or forward_dot < -0.5:
			throttle = brake
			brake = 0.0
			is_reversing = true
	
		
	var steer_multiplier = calculate_combined_steer_multiplier(speed_kph)
	
	var target_angle = steer_input * max_steer_angle * steer_multiplier
	
	# Speed-dependent steering rate: slower at low speed, faster at high speed
	var effective_steer_speed: float
	if speed_kph < 30.0:
		# Low speed: heavy, sluggish steering (prevents whipping side to side)
		effective_steer_speed = lerp(2.0, 4.0, clamp(speed_kph / 30.0, 0.0, 1.0))
	else:
		# High speed: quicker response for corrections (but angle is already limited)
		effective_steer_speed = lerp(4.0, 6.0, clamp((speed_kph - 30.0) / 70.0, 0.0, 1.0))
	
	current_steer_angle = lerp(current_steer_angle, target_angle, effective_steer_speed * delta)
	
	for wheel in wheels:
		wheel.force_raycast_update()
	
	apply_rear_downforce()
	apply_yaw_damping()
	apply_straight_line_assist()
	apply_slide_recovery()
	apply_active_anti_roll()
	detect_surfaces(delta)
	apply_anti_rollover_force()
	
	if enable_anti_pitch:
		apply_anti_pitch_control()
	
	apply_resistance_forces()
	
	total_drive_force = 0.0
	total_lat_force = 0.0
	
	# Calculate body slip angle for debug
	if linear_velocity.length() > 1.0:
		var forward_dir = -global_transform.basis.z
		var velocity_dir = linear_velocity.normalized()
		var lateral_dir = global_transform.basis.x
		var lateral_velocity = velocity_dir.dot(lateral_dir)
		var forward_velocity = velocity_dir.dot(forward_dir)
		body_slip_angle = atan2(lateral_velocity, forward_velocity)
	else:
		body_slip_angle = 0.0
	
	# Calculate yaw rate
	yaw_rate = angular_velocity.dot(global_transform.basis.y)
	
	for i in range(wheels.size()):
		var wheel = wheels[i]
		if wheel.is_colliding():
			apply_suspension_force(wheel, i, delta)
			apply_tire_force(wheel, i, throttle, brake, delta, steer_multiplier, is_reversing)
		else:
			prev_compression[i] = 0.0
			prev_length[i] = get_blended_rest_length(i)
			wheel_slip_angles[i] = 0.0
			wheel_normal_loads[i] = 0.0
			wheel_drive_forces[i] = 0.0
			wheel_lateral_forces[i] = 0.0
	
	var arb_front = lerp(arb_stiffness_front_gravel, arb_stiffness_front_tarmac, 
		(suspension_blend[0] + suspension_blend[1]) * 0.5)
	var arb_rear = lerp(arb_stiffness_rear_gravel, arb_stiffness_rear_tarmac, 
		(suspension_blend[2] + suspension_blend[3]) * 0.5)
	
	apply_arb(0, 1, arb_front)
	apply_arb(2, 3, arb_rear)
	
	update_visuals(delta)
	
	debug_timer += delta
	
	if enable_detailed_debug and debug_timer >= debug_interval:
		if throttle > debug_throttle_threshold or brake > 0.5:
			if speed_kph >= debug_min_speed and speed_kph <= debug_max_speed:
				print_detailed_debug(speed_kph, throttle, steer_input)
				debug_timer = 0.0

func print_detailed_debug(speed_kph: float, throttle: float, steer_input: float):
	var front_load = wheel_normal_loads[0] + wheel_normal_loads[1]
	var rear_load = wheel_normal_loads[2] + wheel_normal_loads[3]
	var total_load = front_load + rear_load
	var front_compression = (prev_compression[0] + prev_compression[1]) * 0.5
	var rear_compression = (prev_compression[2] + prev_compression[3]) * 0.5
	var front_drive = wheel_drive_forces[0] + wheel_drive_forces[1]
	var rear_drive = wheel_drive_forces[2] + wheel_drive_forces[3]
	var front_lateral = wheel_lateral_forces[0] + wheel_lateral_forces[1]
	var rear_lateral = wheel_lateral_forces[2] + wheel_lateral_forces[3]
	
	print("\n╔════════════════════════════════════════════╗")
	print("║        RALLY CAR DEBUG - %.1f km/h       ║" % speed_kph)
	print("╠════════════════════════════════════════════╣")
	print("║ INPUTS                                     ║")
	print("║  Throttle: %.0f%%  |  Steering: %.2f      ║" % [throttle * 100, steer_input])
	print("║  Steer Angle: %.2f rad (%.0f°)            ║" % [current_steer_angle, rad_to_deg(current_steer_angle)])
	print("╠════════════════════════════════════════════╣")
	print("║ VEHICLE DYNAMICS                           ║")
	print("║  Body Slip Angle: %.2f rad (%.1f°)        ║" % [body_slip_angle, rad_to_deg(body_slip_angle)])
	print("║  Yaw Rate: %.2f rad/s                     ║" % yaw_rate)
	print("║  COM Position: (%.2f, %.2f, %.2f)        ║" % [center_of_mass.x, center_of_mass.y, center_of_mass.z])
	print("╠════════════════════════════════════════════╣")
	print("║ WEIGHT DISTRIBUTION                        ║")
	print("║  Front: %.0fN (%.0f%%)                    ║" % [front_load, (front_load / total_load) * 100])
	print("║  Rear:  %.0fN (%.0f%%)                    ║" % [rear_load, (rear_load / total_load) * 100])
	print("║  F Comp: %.3fm  |  R Comp: %.3fm        ║" % [front_compression, rear_compression])
	print("╠════════════════════════════════════════════╣")
	print("║ POWER DISTRIBUTION (F/R Split: %.0f/%.0f)  ║" % [(1.0 - torque_split) * 100, torque_split * 100])
	print("║  Front: %.0fN  |  Rear: %.0fN            ║" % [front_drive, rear_drive])
	print("║  Total Drive Force: %.0fN                 ║" % total_drive_force)
	print("╠════════════════════════════════════════════╣")
	print("║ INDIVIDUAL WHEEL DATA                      ║")
	print("║                                            ║")
	print("║  FL: Load %.0fN | Drive %.0fN/%.0fN      ║" % [wheel_normal_loads[0], wheel_drive_forces[0], wheel_traction_limits[0]])
	print("║      Slip %.2f° | Lat %.0fN              ║" % [rad_to_deg(wheel_slip_angles[0]), wheel_lateral_forces[0]])
	print("║                                            ║")
	print("║  FR: Load %.0fN | Drive %.0fN/%.0fN      ║" % [wheel_normal_loads[1], wheel_drive_forces[1], wheel_traction_limits[1]])
	print("║      Slip %.2f° | Lat %.0fN              ║" % [rad_to_deg(wheel_slip_angles[1]), wheel_lateral_forces[1]])
	print("║                                            ║")
	print("║  RL: Load %.0fN | Drive %.0fN/%.0fN      ║" % [wheel_normal_loads[2], wheel_drive_forces[2], wheel_traction_limits[2]])
	print("║      Slip %.2f° | Lat %.0fN              ║" % [rad_to_deg(wheel_slip_angles[2]), wheel_lateral_forces[2]])
	print("║                                            ║")
	print("║  RR: Load %.0fN | Drive %.0fN/%.0fN      ║" % [wheel_normal_loads[3], wheel_drive_forces[3], wheel_traction_limits[3]])
	print("║      Slip %.2f° | Lat %.0fN              ║" % [rad_to_deg(wheel_slip_angles[3]), wheel_lateral_forces[3]])
	print("╠════════════════════════════════════════════╣")
	print("║ GRIP USAGE (Drive/Limit %)                ║")
	print("║  FL: %.0f%%  |  FR: %.0f%%                  ║" % [
		(wheel_drive_forces[0] / wheel_traction_limits[0] * 100) if wheel_traction_limits[0] > 0 else 0,
		(wheel_drive_forces[1] / wheel_traction_limits[1] * 100) if wheel_traction_limits[1] > 0 else 0
	])
	print("║  RL: %.0f%%  |  RR: %.0f%%                  ║" % [
		(wheel_drive_forces[2] / wheel_traction_limits[2] * 100) if wheel_traction_limits[2] > 0 else 0,
		(wheel_drive_forces[3] / wheel_traction_limits[3] * 100) if wheel_traction_limits[3] > 0 else 0
	])
	print("╚════════════════════════════════════════════╝\n")

# ==============================================================================
# SPEED-SENSITIVE STEERING (LOW & HIGH SPEED)
# ==============================================================================

func calculate_combined_steer_multiplier(speed_kph: float) -> float:
	# Single smooth curve: low at very low speed, peaks in mid range, reduces at high speed
	
	# Phase 1: Low-speed ramp up (0 to peak_speed)
	var peak_speed = 45.0  # Speed where steering is at maximum
	var low_speed_floor = 0.15  # Minimum ratio at very low speed
	
	# Phase 2: High-speed ramp down (peak_speed to max)
	var high_speed_floor = 0.08  # Minimum ratio at very high speed
	var full_reduction_speed = 120.0  # Speed where minimum is reached
	
	var result: float
	
	if speed_kph <= 0.0:
		result = low_speed_floor
	elif speed_kph < peak_speed:
		# Ramp UP from low_speed_floor to 1.0
		var factor = speed_kph / peak_speed
		factor = factor * factor * (3.0 - 2.0 * factor)  # Smoothstep
		result = lerp(low_speed_floor, 1.0, factor)
	elif speed_kph <= peak_speed + 10.0:
		# Small plateau at 1.0 (45-55 km/h) for natural feel
		result = 1.0
	elif speed_kph >= full_reduction_speed:
		result = high_speed_floor
	else:
		# Ramp DOWN from 1.0 to high_speed_floor
		var range_start = peak_speed + 10.0  # 55 km/h
		var speed_range = full_reduction_speed - range_start
		var speed_in_range = speed_kph - range_start
		var factor = speed_in_range / speed_range
		factor = factor * factor * (3.0 - 2.0 * factor)  # Smoothstep
		result = lerp(1.0, high_speed_floor, factor)
	
	return result

# ==============================================================================
# ANTI-PITCH CONTROL
# ==============================================================================

func apply_anti_pitch_control():
	var throttle = Input.get_action_strength("accelerate")
	var brake = Input.get_action_strength("brake")
	var speed_kph = linear_velocity.length() * 3.6
	
	# Skip during reverse (brake held, no throttle, low speed or moving backward)
	var forward_dot = linear_velocity.dot(-global_transform.basis.z)
	if brake > 0.1 and throttle < 0.1 and (speed_kph < 5.0 or forward_dot < -0.5):
		return
	
	if speed_kph < 5.0:
		return
	
	var front_compression = (prev_compression[0] + prev_compression[1]) * 0.5
	var rear_compression = (prev_compression[2] + prev_compression[3]) * 0.5
	var compression_diff = front_compression - rear_compression
	
	# === BRAKING: Force weight forward ===
	if brake > 0.1:
		# Target: front should be MORE compressed than rear
		# When comp_diff < 0, rear is winning (wrong)
		# Scale force based on how wrong it is, using spring-level forces
		
		var target_diff = 0.06  # Front should be 2cm more compressed
		var error = target_diff - compression_diff  # Positive when we need more front compression
		
		if error > 0.0:
			# Use spring_stiffness-scale forces — we need to compete with 100,000 N/m springs
			# error of 0.05m * 500,000 = 25,000N per wheel
			var correction_per_wheel = error * 600000.0 * brake
			correction_per_wheel = min(correction_per_wheel, 35000.0)  # Cap per wheel
			
			# Push FRONT wheels DOWN
			for i in [0, 1]:
				if wheels[i].is_colliding():
					apply_force(Vector3.DOWN * correction_per_wheel, wheels[i].global_position - global_position)
			
			# Push REAR wheels UP
			for i in [2, 3]:
				if wheels[i].is_colliding():
					apply_force(Vector3.UP * correction_per_wheel, wheels[i].global_position - global_position)
			
	
	# === ACCELERATION: Prevent rear squat ===
	elif throttle > 0.1 and brake < 0.1:
		# During acceleration, we WANT weight on the rear for traction
		# Apply a small downforce to rear proportional to throttle and speed
		var speed_factor = clamp(speed_kph / 80.0, 0.0, 1.0)
		var rear_help = throttle * speed_factor * 3000.0  # Up to 3000N per rear wheel
		
		for i in [2, 3]:
			if wheels[i].is_colliding():
				apply_force(Vector3.DOWN * rear_help, wheels[i].global_position - global_position)

	
	# === PITCH DAMPING ===
	var pitch_velocity = angular_velocity.dot(global_transform.basis.x)
	var pitch_damping = -global_transform.basis.x * pitch_velocity * pitch_damping_strength
	apply_torque(pitch_damping)

func apply_rear_downforce():
	# Don't fight natural weight transfer during braking
	var brake = Input.get_action_strength("brake")
	if brake > 0.1:
		return
	
	var rear_compression = (prev_compression[2] + prev_compression[3]) * 0.5
	
	if rear_compression < 0.020:
		for i in [2, 3]:
			var down_force = Vector3.DOWN * 15000.0
			apply_force(down_force, wheels[i].global_position - global_position)
		

func apply_yaw_damping():
	var speed_kph = linear_velocity.length() * 3.6
	
	# Only apply at low-medium speeds where oversteer is worst
	if speed_kph < 5.0 or speed_kph > 80.0:
		return
	
	# Get yaw rate (rotation around Y axis)
	var yaw_velocity = angular_velocity.dot(global_transform.basis.y)
	
	# If rotating too fast, apply counter-torque
	if abs(yaw_velocity) > 1.5:  # More than 1.5 rad/s = too spinny
		var damping_strength = 8000.0  # Adjust this to taste
		var counter_torque = -global_transform.basis.y * yaw_velocity * damping_strength
		apply_torque(counter_torque)
		# ==============================================================================
# RESISTANCE FORCES
# ==============================================================================

func apply_resistance_forces():
	var speed = linear_velocity.length()
	
	if speed < 0.1:
		return
	
	var velocity_dir = linear_velocity.normalized()
	var rolling_force = velocity_dir * -rolling_resistance
	var air_force = velocity_dir * -air_resistance * speed * speed
	
	apply_central_force(rolling_force + air_force)

# ==============================================================================
# SURFACE DETECTION & SUSPENSION BLENDING
# ==============================================================================

func detect_surfaces(delta: float):
	for i in range(wheels.size()):
		var wheel = wheels[i]
		var target_blend: float
		var new_surface: String = wheel_surfaces[i]
		
		if wheel.is_colliding():
			var collider = wheel.get_collider()
			if collider and collider.is_in_group("Gravel"):
				new_surface = "Gravel"
				target_blend = 0.0
			else:
				new_surface = "Tarmac"
				target_blend = 1.0
			
			# Print when surface changes
			if new_surface != prev_wheel_surfaces[i]:
				var wheel_names = ["FL", "FR", "RL", "RR"]
				print("🏁 %s: %s → %s" % [wheel_names[i], prev_wheel_surfaces[i], new_surface])
			
			wheel_surfaces[i] = new_surface
			prev_wheel_surfaces[i] = new_surface
		else:
			target_blend = suspension_blend[i]
		
		suspension_blend[i] = lerp(suspension_blend[i], target_blend, 
			suspension_blend_speed * delta)

func get_blended_suspension_params(index: int) -> Dictionary:
	var blend = suspension_blend[index]
	
	return {
		"spring_stiffness": lerp(spring_stiffness_gravel, spring_stiffness_tarmac, blend),
		"spring_progressive_rate": lerp(spring_progressive_rate_gravel, spring_progressive_rate_tarmac, blend),
		"damping_compression": lerp(damping_compression_gravel, damping_compression_tarmac, blend),
		"damping_rebound": lerp(damping_rebound_gravel, damping_rebound_tarmac, blend),
		"rest_length": lerp(rest_length_gravel, rest_length_tarmac, blend),
		"max_compression": lerp(max_compression_gravel, max_compression_tarmac, blend),
		"bump_stop_stiffness": lerp(bump_stop_stiffness_gravel, bump_stop_stiffness_tarmac, blend)
	}

func get_blended_rest_length(index: int) -> float:
	return lerp(rest_length_gravel, rest_length_tarmac, suspension_blend[index])

# ==============================================================================
# SUSPENSION & TIRE LOGIC
# ==============================================================================

func apply_suspension_force(wheel: RayCast3D, index: int, delta: float):
	var params = get_blended_suspension_params(index)
	
	var contact_point = wheel.get_collision_point()
	var dist = wheel.global_position.distance_to(contact_point)
	var current_length = clamp(dist, 0.0, params.rest_length)
	var compression = params.rest_length - current_length
	
	var compression_ratio = compression / params.rest_length
	var progressive_multiplier = 1.0 + (compression_ratio * compression_ratio * params.spring_progressive_rate)
	var spring_force = compression * params.spring_stiffness * progressive_multiplier
	
	if compression > params.max_compression:
		var bump_compression = compression - params.max_compression
		var bump_force = bump_compression * params.bump_stop_stiffness
		spring_force += bump_force
	
	var length_change = current_length - prev_length[index]
	var suspension_velocity = length_change / delta
	
	var damper_force: float
	if suspension_velocity < 0:
		damper_force = -suspension_velocity * params.damping_compression
	else:
		var rebound_multiplier = 1.0
		if compression_ratio > 0.5:
			rebound_multiplier = 1.0 - ((compression_ratio - 0.5) * 1.0)
			rebound_multiplier = clamp(rebound_multiplier, 0.5, 1.0)
		
		damper_force = -suspension_velocity * params.damping_rebound * rebound_multiplier
	
	var total_force = spring_force + damper_force
	total_force = max(total_force, 0.0)
	total_force = min(total_force, max_suspension_force)
	
	var ground_normal = wheel.get_collision_normal()
	var force_vector = ground_normal * total_force
	var local_pos = wheel.global_position - global_position
	apply_force(force_vector, local_pos)
	
	prev_compression[index] = compression
	prev_length[index] = current_length

func apply_straight_line_assist():
	var throttle = Input.get_action_strength("accelerate")
	var steer_input = abs(Input.get_axis("steer_right", "steer_left"))
	var speed_kph = linear_velocity.length() * 3.6
	
	# Count up if accelerating straight, reset if not
	if throttle > 0.5 and steer_input < 0.1 and speed_kph > 5.0:
		straight_accel_timer += get_physics_process_delta_time()
	else:
		straight_accel_timer = 0.0
		return
	
	# Speed-aware activation delay:
	# From dead stop (< 15 km/h when timer started): wait 2.5 seconds
	# Already moving (> 40 km/h): wait 1.5 seconds
	# In between: interpolate
	var activation_delay: float
	if speed_kph < 15.0:
		activation_delay = 1.5
	elif speed_kph > 40.0:
		activation_delay = 0.5
	else:
		var blend = (speed_kph - 15.0) / 25.0
		activation_delay = lerp(2.5, 1.5, blend)
	
	if straight_accel_timer < activation_delay:
		return
	
	# Gradually ramp up correction strength over 2 seconds after activation
	var time_since_activation = straight_accel_timer - activation_delay
	var ramp_factor = clamp(time_since_activation / 2.0, 0.0, 1.0)
	# Ease in: starts very gentle, builds up
	ramp_factor = ramp_factor * ramp_factor  # Quadratic ease-in
	
	# Calculate how much we're drifting sideways
	var lateral_dir = global_transform.basis.x
	var lateral_velocity = linear_velocity.dot(lateral_dir)
	
	# Only correct if there's meaningful drift (ignore tiny amounts)
	if abs(lateral_velocity) < 0.1:
		return
	
	# Push against sideways drift — gentle, player shouldn't feel it
	var correction_force = -lateral_dir * lateral_velocity * mass * 1.0 * ramp_factor
	apply_central_force(correction_force)
	
	# Gently kill yaw rotation
	var yaw_velocity = angular_velocity.dot(global_transform.basis.y)
	if abs(yaw_velocity) > 0.02:
		var yaw_correction = -global_transform.basis.y * yaw_velocity * 8000.0 * ramp_factor
		apply_torque(yaw_correction)
		
func apply_active_anti_roll():
	# SIMPLE, STRONG VERSION
	
	# 1. STRONG GEOMETRIC ANTI-ROLL
	var world_up = Vector3.UP
	var right_vector = global_transform.basis.x
	var roll_angle = right_vector.dot(world_up)
	
	if abs(roll_angle) > 0.08:
		var correction_strength = 20000.0 * abs(roll_angle)
		var roll_axis = -global_transform.basis.z
		
		if roll_angle > 0:
			apply_torque(roll_axis * -correction_strength)
		else:
			apply_torque(roll_axis * correction_strength)
	
	# 2. INCREASED MINIMUM LOAD TARGET
	var brake = Input.get_action_strength("brake")
	for i in range(4):
		if wheels[i].is_colliding():
			var wheel_load = wheel_normal_loads[i]
			if brake > 0.1 and i >= 2:
				continue
			
			if wheel_load < 5500.0:
				var deficit = 5500.0 - wheel_load
				var emergency_downforce = Vector3.DOWN * deficit * 3.0
				apply_force(emergency_downforce, wheels[i].global_position - global_position)
		else:
			var strong_downforce = Vector3.DOWN * 15000.0
			apply_force(strong_downforce, wheels[i].global_position - global_position)
	
	# 3. ACTIVE LOAD TRANSFER
	if abs(current_steer_angle) > 0.25:
		var turn_direction = sign(current_steer_angle)
		
		var outside_indices = [0, 2] if turn_direction > 0 else [1, 3]
		var inside_indices = [1, 3] if turn_direction > 0 else [0, 2]
		
		var outside_load = wheel_normal_loads[outside_indices[0]] + wheel_normal_loads[outside_indices[1]]
		var inside_load = wheel_normal_loads[inside_indices[0]] + wheel_normal_loads[inside_indices[1]]
		
		var total_load = outside_load + inside_load
		if total_load > 100:
			var inside_ratio = inside_load / total_load
			
			# CHANGED: Increase from 0.45 to 0.48 (more help)
			if inside_ratio < 0.48:
				var transfer_force = 28000.0 * (0.48 - inside_ratio)  # INCREASED from 25000
				
				for idx in inside_indices:
					var down_force = Vector3.DOWN * transfer_force
					apply_force(down_force, wheels[idx].global_position - global_position)


func apply_slide_recovery():
	var speed_kph = linear_velocity.length() * 3.6
	
	# Only active at medium-high speeds with no steering input
	if speed_kph < 30.0 or abs(Input.get_axis("steer_right", "steer_left")) > 0.1:
		return
	
	# Calculate if we're sliding sideways
	if linear_velocity.length() > 5.0:
		var forward_dir = -global_transform.basis.z
		var velocity_dir = linear_velocity.normalized()
		var lateral_dir = global_transform.basis.x
		
		var lateral_velocity = velocity_dir.dot(lateral_dir)
		var forward_velocity = velocity_dir.dot(forward_dir)
		var current_slip = atan2(lateral_velocity, forward_velocity)
		
		# If sliding more than 15 degrees with no steering input
		if abs(current_slip) > 0.26:  # ~15 degrees
			# Apply counter-yaw torque to straighten out
			var yaw_velocity = angular_velocity.dot(global_transform.basis.y)
			var correction_strength = 12000.0 * abs(current_slip)  # Proportional to slide angle
			
			# Counter the yaw rotation
			var counter_torque = -global_transform.basis.y * yaw_velocity * correction_strength
			apply_torque(counter_torque)
			
			# Also reduce rear power during slide to help recovery
			if abs(current_slip) > 0.35:  # ~20 degrees - serious slide
				# This is handled in the tire force calculation (see below)
				pass
					
func apply_arb(left_idx: int, right_idx: int, stiffness: float):
	var w_l = wheels[left_idx]
	var w_r = wheels[right_idx]
	
	if w_l.is_colliding() and w_r.is_colliding():
		var rest_l = get_blended_rest_length(left_idx)
		var rest_r = get_blended_rest_length(right_idx)
		
		var comp_diff = prev_compression[left_idx] - prev_compression[right_idx]
		
		var max_compression_side = max(prev_compression[left_idx], prev_compression[right_idx])
		var avg_rest = (rest_l + rest_r) * 0.5
		var compression_ratio = max_compression_side / avg_rest
		
		var arb_reduction = 1.0 - (compression_ratio * compression_ratio * 0.7)
		arb_reduction = clamp(arb_reduction, 0.3, 1.0)
		
		var arb_force = comp_diff * stiffness * arb_reduction
		
		var left_normal = w_l.get_collision_normal()
		var right_normal = w_r.get_collision_normal()
		
		apply_force(left_normal * -arb_force, w_l.global_position - global_position)
		apply_force(right_normal * arb_force, w_r.global_position - global_position)

func apply_anti_rollover_force():
	var up_vector = global_transform.basis.y
	var world_up = Vector3.UP
	var roll_angle = up_vector.angle_to(world_up)
	
	if roll_angle > 0.3:
		var roll_axis = up_vector.cross(world_up).normalized()
		var correction_strength = (roll_angle - 0.3) * 20000.0
		correction_strength = min(correction_strength, 30000.0)
		
		apply_torque(roll_axis * correction_strength)
		
		var right_vector = global_transform.basis.x
		var roll_direction = sign(right_vector.dot(world_up))
		
		for i in range(4):
			var wheel = wheels[i]
			var is_right_side = (i == 1 or i == 3)
			
			if wheel.is_colliding():
				if (is_right_side and roll_direction < 0) or (!is_right_side and roll_direction > 0):
					var down_force = Vector3.DOWN * correction_strength * 0.3
					apply_force(down_force, wheel.global_position - global_position)

func apply_tire_force(wheel: RayCast3D, index: int, throttle: float, brake: float, delta: float, steer_multiplier: float, is_reversing: bool = false):
	var surface = wheel_surfaces[index]
	var tire_params = get_pacejka_params(surface, index)
	
	var wheel_basis = wheel.global_transform.basis
	if index < 2:
		wheel_basis = wheel_basis.rotated(wheel.global_transform.basis.y, current_steer_angle)
	
	var forward_dir = -wheel_basis.z
	var right_dir = wheel_basis.x
	var wheel_vel = get_velocity_at_point(wheel.get_collision_point())
	var v_long = forward_dir.dot(wheel_vel)
	var v_lat = right_dir.dot(wheel_vel)
	
	var speed = wheel_vel.length()
	var v_long_safe = max(abs(v_long), 0.5)
	var slip_angle = atan2(v_lat, v_long_safe)
	
	if speed < 2.0:
		var speed_factor = speed / 2.0
		slip_angle *= speed_factor
	
	# Store for debug
	wheel_slip_angles[index] = slip_angle
	
	# Calculate normal load
	var base_load = (mass / 4.0) * 9.8
	var params = get_blended_suspension_params(index)
	var spring_load = prev_compression[index] * params.spring_stiffness
	var normal_load = base_load + (spring_load * 0.5)
	normal_load = max(normal_load, 100.0)
	
	# Store for debug
	wheel_normal_loads[index] = normal_load
	
	# Load sensitivity
	var load_sensitivity = 1.0
	var optimal_load = base_load * 1.2
	if normal_load > optimal_load:
		load_sensitivity = optimal_load / normal_load
		load_sensitivity = clamp(load_sensitivity, 0.7, 1.0)
	
	# === LATERAL FORCE (Steering) ===
		# === LATERAL FORCE (Steering) ===
	var lateral_coeff = pacejka_formula(slip_angle, tire_params)
	var lat_force_mag = lateral_coeff * normal_load * load_sensitivity
	
	# Low-speed lateral grip reduction — use CAR speed, not wheel speed
	# Gentler ramp: 60% grip at 0 km/h, 100% at 30 km/h
		# Low-speed lateral grip reduction — prevents snappy rotation at low speed
	var car_speed_ms = linear_velocity.length()
	var low_speed_lat_scale = clamp(car_speed_ms / 8.5, 0.6, 1.0)
	if not is_reversing:
		lat_force_mag *= low_speed_lat_scale
	
	if reduce_lateral_grip_with_speed and not is_reversing:
		lat_force_mag *= steer_multiplier
	
	if reduce_lateral_grip_with_speed:
		lat_force_mag *= steer_multiplier
	
	if is_handbrake_active and index >= 2:
		lat_force_mag *= 0.2
	
	var lat_force_vec = -right_dir * lat_force_mag
	total_lat_force += abs(lat_force_mag)
	
	# Store for debug
	wheel_lateral_forces[index] = abs(lat_force_mag)
	
	# === LONGITUDINAL FORCE (Drive/Brake) ===
	var drive_force_mag = 0.0
	var is_braking = false
	
	if is_handbrake_active and index >= 2:  # Handbrake: ONLY rear wheels (correct!)
		var brake_direction = -1.0 if v_long > 0 else 1.0
		drive_force_mag = brake_direction * handbrake_force
		is_braking = true
		total_drive_force += abs(drive_force_mag)
	elif brake > 0.01:  # Regular brake: ALL wheels (fixed!)
		var brake_direction = -1.0 if v_long > 0 else 1.0
		# Front wheels get more braking (60/40 split is typical)
		var brake_bias = 0.6 if index < 2 else 0.4
		drive_force_mag = brake_direction * brake_force * brake * brake_bias * 2.5  # 2.5 to compensate for split
		is_braking = true
		total_drive_force += abs(drive_force_mag)
	elif throttle > 0.01:
		var car_speed = linear_velocity.length()
		var top_speed_ms = top_speed_kph / 3.6
		var speed_ratio = clamp(car_speed / top_speed_ms, 0.0, 1.0)
		
		var power_ratio = 1.0 - (speed_ratio * power_curve_falloff)
		power_ratio = max(power_ratio, min_power_ratio)
		
		var total_drive = engine_power * throttle * power_ratio
		
		# Reverse: flip drive direction
		if is_reversing:
			total_drive = -total_drive
		
		var torque_multiplier = lerp(gravel_torque_multiplier, tarmac_torque_multiplier, suspension_blend[index])
		total_drive *= torque_multiplier
		
		if index >= 2:  # Rear wheels
			if abs(body_slip_angle) > 0.26:
				var slide_reduction = 1.0 - (abs(body_slip_angle) - 0.26) * 1.5
				slide_reduction = clamp(slide_reduction, 0.5, 1.0)
				total_drive *= slide_reduction
		
		drive_force_mag = calculate_awd_torque(index, total_drive)
		
		total_drive_force += drive_force_mag
	
	# Store for debug
	wheel_drive_forces[index] = abs(drive_force_mag)
	
	# === TRACTION CIRCLE ===
	var slip_angle_abs = abs(slip_angle)
	
	var base_traction_limit = tire_params.D * normal_load * load_sensitivity
	
	var longitudinal_limit: float
	if slip_angle_abs < straight_line_slip_angle:
		var straight_factor = 1.0 - (slip_angle_abs / straight_line_slip_angle)
		longitudinal_limit = base_traction_limit * (1.0 + (longitudinal_grip_multiplier - 1.0) * straight_factor)
	else:
		longitudinal_limit = base_traction_limit
	
	# Store for debug
	wheel_traction_limits[index] = longitudinal_limit
	
	var lateral_limit = base_traction_limit
	
	var long_exceeded = abs(drive_force_mag) > longitudinal_limit
	var lat_exceeded = abs(lat_force_mag) > lateral_limit
	
	if long_exceeded or lat_exceeded:
		if is_handbrake_active and index >= 2:
			drive_force_mag = clamp(drive_force_mag, -longitudinal_limit * 1.5, longitudinal_limit * 1.5)
			lat_force_mag = clamp(lat_force_mag, -lateral_limit * 0.3, lateral_limit * 0.3)
		elif is_braking:
			drive_force_mag = clamp(drive_force_mag, -longitudinal_limit * 0.9, longitudinal_limit * 0.9)
			lat_force_mag = clamp(lat_force_mag, -lateral_limit * 1.0, lateral_limit * 1.0)
		else:
			drive_force_mag = clamp(drive_force_mag, -longitudinal_limit, longitudinal_limit)
			lat_force_mag = clamp(lat_force_mag, -lateral_limit, lateral_limit)
		
		lat_force_vec = -right_dir * lat_force_mag
	
	var force_application_point = wheel.global_position - global_position
	
	if is_braking and not is_handbrake_active:
		# Apply lateral at the wheel (for steering feel)
		apply_force(lat_force_vec, force_application_point)
		
		# Apply braking force at a point shifted toward CoM vertically
		# This reduces the pitch moment arm
		var brake_point = force_application_point
		brake_point.y = center_of_mass.y  # Apply at CoM height instead of wheel height
		apply_force(forward_dir * drive_force_mag, brake_point)
	else:
		apply_force(lat_force_vec + (forward_dir * drive_force_mag), force_application_point)


# ==============================================================================
# VISUALS
# ==============================================================================

# ==============================================================================
# VISUALS (STRICT Y-AXIS ONLY - NO X/Z MOVEMENT)
# ==============================================================================

func update_visuals(delta: float):
	var mesh_list = [mesh_fl, mesh_fr, mesh_rl, mesh_rr]
	
	for i in range(4):
		var mesh = mesh_list[i]
		var ray = wheels[i]
		
		if !mesh or !ray: continue
		
		# 1. HARD RESET: Locks X/Z position, Rotation, and Scale to your editor setup
		mesh.transform = initial_transforms[i]
		
		# 2. CALCULATE Y-OFFSET (Suspension)
		var params = get_blended_suspension_params(i)
		var current_dist = get_blended_rest_length(i) # Default to hanging
		
		if ray.is_colliding():
			var hit_point = ray.get_collision_point()
			current_dist = ray.global_position.distance_to(hit_point)
			
			# Limit visual compression so the tire doesn't clip through the fender
			var max_visual_compression = params.rest_length - params.max_compression
			current_dist = max(current_dist, max_visual_compression)
			
		# How far down from the initial Top position should the wheel center be?
		var drop_distance = current_dist - wheel_radius
		
		# 3. APPLY Y-MOVEMENT ONLY
		# We modify ONLY the local Y position. X and Z are untouched.
		mesh.position.y = initial_transforms[i].origin.y - drop_distance
		
		# 4. STEERING
		if i < 2: 
			mesh.rotate_object_local(Vector3.UP, current_steer_angle)
		
		# 5. SPIN
		var speed = linear_velocity.length()
		var forward_dot = linear_velocity.dot(-global_transform.basis.z)
		var dir = 1.0 if forward_dot > 0 else -1.0
		
		if ray.is_colliding():
			accumulated_spin[i] += speed * delta * dir * 0.1
		
		# Uses 'spin_axis' which is Vector3.UP (Y)
		mesh.rotate_object_local(spin_axis, accumulated_spin[i])

# ==============================================================================
# HELPERS
# ==============================================================================

func get_pacejka_params(surface: String, wheel_index: int) -> Dictionary:
	var is_rear = wheel_index >= 2
	
	if surface == "Gravel":
		if is_rear:
			return { "B": 6.5, "C": 2.0, "D": 1.5, "E": 0.2 }  # REDUCED: 2.0 → 1.5
		else:
			return { "B": 6.5, "C": 2.0, "D": 1.7, "E": 0.2 }
	else:  # Tarmac
		if is_rear:
			return { "B": 8.0, "C": 1.9, "D": 1.8, "E": -0.5 }  # REDUCED: 2.4 → 1.8
		else:
			return { "B": 8.0, "C": 1.9, "D": 2.0, "E": -0.5 }
	

func pacejka_formula(slip: float, p: Dictionary) -> float:
	var x = slip * p.B
	return p.D * sin(p.C * atan(x - p.E * (x - atan(x))))

func calculate_awd_torque(index: int, total_drive: float) -> float:
	var speed_kph = linear_velocity.length() * 3.6
	var current_split = calculate_dynamic_torque_split(speed_kph)
	
	if index < 2:  # Front wheels
		return (total_drive * (1.0 - current_split)) / 2.0
	else:  # Rear wheels
		return (total_drive * current_split) / 2.0


func get_velocity_at_point(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - global_position)

func calculate_dynamic_torque_split(speed_kph: float) -> float:
	if not enable_dynamic_torque:
		return torque_split
	
	# Below transition speed: use low-speed split (more front bias)
	if speed_kph <= 0.0:
		return low_speed_rear_split
	
	# Above transition speed: use high-speed split (balanced)
	if speed_kph >= torque_transition_speed_kph:
		return high_speed_rear_split
	
	# Between: smooth interpolation
	var factor = speed_kph / torque_transition_speed_kph
	factor = factor * factor * (3.0 - 2.0 * factor)  # Smoothstep
	
	return lerp(low_speed_rear_split, high_speed_rear_split, factor)
