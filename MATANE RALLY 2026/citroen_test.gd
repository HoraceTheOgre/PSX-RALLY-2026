extends RigidBody3D

# ==============================================================================
# RALLY CONTROLLER (SPEED-ADAPTIVE STEERING - LOW & HIGH SPEED)
# ==============================================================================

# --- Configuration: Suspension (Gravel) ---
@export_group("Suspension System - Gravel")
@export var spring_stiffness_gravel: float = 100000.0
@export var spring_progressive_rate_gravel: float = 2.0
@export var damping_compression_gravel: float = 20000.0
@export var damping_rebound_gravel: float = 18000.0
@export var rest_length_gravel: float = 0.6
@export var max_compression_gravel: float = 0.5
@export var bump_stop_stiffness_gravel: float = 100000.0
@export var arb_stiffness_front_gravel: float = 6000.0
@export var arb_stiffness_rear_gravel: float = 3000.0

# --- Configuration: Suspension (Tarmac) ---
@export_group("Suspension System - Tarmac")
@export var spring_stiffness_tarmac: float = 80000.0
@export var spring_progressive_rate_tarmac: float = 1.2
@export var damping_compression_tarmac: float = 16000.0
@export var damping_rebound_tarmac: float = 14000.0
@export var rest_length_tarmac: float = 0.5
@export var max_compression_tarmac: float = 0.4
@export var bump_stop_stiffness_tarmac: float = 120000.0
@export var arb_stiffness_front_tarmac: float = 10000.0
@export var arb_stiffness_rear_tarmac: float = 8000.0

# --- Configuration: Suspension Blending ---
@export_group("Suspension Adaptation")
@export var suspension_blend_speed: float = 2.0
@export var wheel_radius: float = 0.35
@export var max_suspension_force: float = 50000.0

# --- Configuration: Anti-Pitch ---
@export_group("Anti-Pitch Control")
@export var enable_anti_pitch: bool = true
@export var anti_pitch_strength: float = 30000.0
@export var pitch_damping_strength: float = 15000.0

# --- Configuration: Drivetrain ---
@export_group("Drivetrain")
@export var engine_power: float = 20000.0
@export var power_curve_falloff: float = 0.05
@export var top_speed_kph: float = 220.0
@export var torque_split: float = 0.5
@export var min_power_ratio: float = 0.85

# --- Configuration: Surface-Specific Torque ---
@export_group("Surface Torque Multipliers")
@export var gravel_torque_multiplier: float = 1.5
@export var tarmac_torque_multiplier: float = 1.0

# --- Configuration: Braking & Resistance ---
@export_group("Braking & Resistance")
@export var brake_force: float = 15000.0
@export var handbrake_force: float = 40000.0
@export var rolling_resistance: float = 15.0
@export var air_resistance: float = 0.2

# --- Configuration: Steering ---
@export_group("Steering")
@export var max_steer_angle: float = 1.0
@export var steer_speed: float = 6

# LOW-SPEED steering reduction (NEW)
@export_subgroup("Low-Speed Steering")
@export var low_speed_steer_reduction_enabled: bool = true
@export var low_speed_min_kph: float = 10.0           # Minimum steering at 0 km/h
@export var low_speed_max_kph: float = 70          # Full steering above this speed
@export var min_low_speed_steer_ratio: float = 0.3   # At 0 km/h, only 30% steering

# HIGH-SPEED steering reduction
@export_subgroup("High-Speed Steering")
@export var high_speed_reduction_start_kph: float = 70.0
@export var high_speed_reduction_end_kph: float = 100.0
@export var min_high_speed_steer_ratio: float = 0.1
@export var reduce_lateral_grip_with_speed: bool = true

# --- Configuration: Traction ---
@export_group("Traction Circle Override")
@export var longitudinal_grip_multiplier: float = 4.0
@export var straight_line_slip_angle: float = 0.15

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
var suspension_blend: Array[float] = [0.0, 0.0, 0.0, 0.0]

# Debug
var total_drive_force: float = 0.0
var total_lat_force: float = 0.0
var is_handbrake_active: bool = false

func _ready():
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(-0.025, -0.2, 0.1)
	
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
	
	var speed_kph = linear_velocity.length() * 3.6
	var steer_multiplier = calculate_combined_steer_multiplier(speed_kph)
	
	var target_angle = steer_input * max_steer_angle * steer_multiplier
	current_steer_angle = lerp(current_steer_angle, target_angle, steer_speed * delta)
	
	for wheel in wheels:
		wheel.force_raycast_update()
	
	detect_surfaces(delta)
	apply_anti_rollover_force()
	
	if enable_anti_pitch:
		apply_anti_pitch_control()
	
	apply_resistance_forces()
	
	total_drive_force = 0.0
	total_lat_force = 0.0
	
	for i in range(wheels.size()):
		var wheel = wheels[i]
		if wheel.is_colliding():
			apply_suspension_force(wheel, i, delta)
			apply_tire_force(wheel, i, throttle, brake, delta, steer_multiplier)
		else:
			prev_compression[i] = 0.0
			prev_length[i] = get_blended_rest_length(i)
	
	var arb_front = lerp(arb_stiffness_front_gravel, arb_stiffness_front_tarmac, 
		(suspension_blend[0] + suspension_blend[1]) * 0.5)
	var arb_rear = lerp(arb_stiffness_rear_gravel, arb_stiffness_rear_tarmac, 
		(suspension_blend[2] + suspension_blend[3]) * 0.5)
	
	apply_arb(0, 1, arb_front)
	apply_arb(2, 3, arb_rear)
	
	update_visuals(delta)
	
	# Debug
	print("Speed: %.1f km/h | Steer: %.2f | Drive: %.0f N" % [speed_kph, steer_multiplier, total_drive_force])

# ==============================================================================
# SPEED-SENSITIVE STEERING (LOW & HIGH SPEED)
# ==============================================================================

func calculate_combined_steer_multiplier(speed_kph: float) -> float:
	var low_speed_mult = 1.0
	var high_speed_mult = 1.0
	
	# LOW-SPEED REDUCTION (below 30 km/h)
	if low_speed_steer_reduction_enabled and speed_kph < low_speed_max_kph:
		if speed_kph <= low_speed_min_kph:
			low_speed_mult = min_low_speed_steer_ratio
		else:
			var speed_range = low_speed_max_kph - low_speed_min_kph
			var speed_in_range = speed_kph - low_speed_min_kph
			var factor = speed_in_range / speed_range
			
			# Smooth curve
			factor = factor * factor * (3.0 - 2.0 * factor)
			
			low_speed_mult = lerp(min_low_speed_steer_ratio, 1.0, factor)
	
	# HIGH-SPEED REDUCTION (above 70 km/h)
	if speed_kph <= high_speed_reduction_start_kph:
		high_speed_mult = 1.0
	elif speed_kph >= high_speed_reduction_end_kph:
		high_speed_mult = min_high_speed_steer_ratio
	else:
		var speed_range = high_speed_reduction_end_kph - high_speed_reduction_start_kph
		var speed_in_range = speed_kph - high_speed_reduction_start_kph
		var factor = speed_in_range / speed_range
		
		factor = factor * factor * (3.0 - 2.0 * factor)
		
		high_speed_mult = lerp(1.0, min_high_speed_steer_ratio, factor)
	
	# Return the most restrictive multiplier
	return min(low_speed_mult, high_speed_mult)

# ==============================================================================
# ANTI-PITCH CONTROL
# ==============================================================================

func apply_anti_pitch_control():
	var car_forward = -global_transform.basis.z
	var forward_flat = Vector3(car_forward.x, 0, car_forward.z).normalized()
	var pitch_angle = asin(clamp(car_forward.y, -1.0, 1.0))
	
	var front_compression = (prev_compression[0] + prev_compression[1]) * 0.5
	var rear_compression = (prev_compression[2] + prev_compression[3]) * 0.5
	var compression_diff = front_compression - rear_compression
	
	var pitch_correction = Vector3.ZERO
	
	if pitch_angle < -0.05 or compression_diff > 0.05:
		var car_right = global_transform.basis.x
		pitch_correction = car_right * anti_pitch_strength * abs(compression_diff)
	elif pitch_angle > 0.05 or compression_diff < -0.05:
		var car_right = global_transform.basis.x
		pitch_correction = -car_right * anti_pitch_strength * abs(compression_diff)
	
	apply_torque(pitch_correction)
	
	var pitch_velocity = angular_velocity.dot(global_transform.basis.x)
	var pitch_damping = -global_transform.basis.x * pitch_velocity * pitch_damping_strength
	apply_torque(pitch_damping)

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
		
		if wheel.is_colliding():
			var collider = wheel.get_collider()
			if collider and collider.is_in_group("Gravel"):
				wheel_surfaces[i] = "Gravel"
				target_blend = 0.0
			else:
				wheel_surfaces[i] = "Tarmac"
				target_blend = 1.0
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

func apply_tire_force(wheel: RayCast3D, index: int, throttle: float, brake: float, delta: float, steer_multiplier: float):
	var surface = wheel_surfaces[index]
	var tire_params = get_pacejka_params(surface)
	
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
	
	# Calculate normal load
	var base_load = (mass / 4.0) * 9.8
	var params = get_blended_suspension_params(index)
	var spring_load = prev_compression[index] * params.spring_stiffness
	var normal_load = base_load + (spring_load * 0.5)
	normal_load = max(normal_load, base_load * 0.8)
	
	# Load sensitivity
	var load_sensitivity = 1.0
	var optimal_load = base_load * 1.2
	if normal_load > optimal_load:
		load_sensitivity = optimal_load / normal_load
		load_sensitivity = clamp(load_sensitivity, 0.7, 1.0)
	
	# === LATERAL FORCE (Steering) ===
	var lateral_coeff = pacejka_formula(slip_angle, tire_params)
	var lat_force_mag = lateral_coeff * normal_load * load_sensitivity
	
	if reduce_lateral_grip_with_speed:
		lat_force_mag *= steer_multiplier
	
	if is_handbrake_active and index >= 2:
		lat_force_mag *= 0.2
	
	var lat_force_vec = -right_dir * lat_force_mag
	total_lat_force += abs(lat_force_mag)
	
	# === LONGITUDINAL FORCE (Drive/Brake) ===
	var drive_force_mag = 0.0
	var is_braking = false
	
	if is_handbrake_active and index >= 2:
		var brake_direction = -1.0 if v_long > 0 else 1.0
		drive_force_mag = brake_direction * handbrake_force
		is_braking = true
		total_drive_force += abs(drive_force_mag)
	elif brake > 0.01:
		var brake_direction = -1.0 if v_long > 0 else 1.0
		drive_force_mag = brake_direction * brake_force * brake
		is_braking = true
		total_drive_force += abs(drive_force_mag)
	elif throttle > 0.01:
		var car_speed = linear_velocity.length()
		var top_speed_ms = top_speed_kph / 3.6
		var speed_ratio = clamp(car_speed / top_speed_ms, 0.0, 1.0)
		
		var power_ratio = 1.0 - (speed_ratio * power_curve_falloff)
		power_ratio = max(power_ratio, min_power_ratio)
		
		var total_drive = engine_power * throttle * power_ratio
		
		var torque_multiplier = lerp(gravel_torque_multiplier, tarmac_torque_multiplier, suspension_blend[index])
		total_drive *= torque_multiplier
		
		drive_force_mag = calculate_awd_torque(index, total_drive)
		
		total_drive_force += drive_force_mag
	
	# === TRACTION CIRCLE ===
	var slip_angle_abs = abs(slip_angle)
	
	var base_traction_limit = tire_params.D * normal_load * load_sensitivity
	
	var longitudinal_limit: float
	if slip_angle_abs < straight_line_slip_angle:
		var straight_factor = 1.0 - (slip_angle_abs / straight_line_slip_angle)
		longitudinal_limit = base_traction_limit * (1.0 + (longitudinal_grip_multiplier - 1.0) * straight_factor)
	else:
		longitudinal_limit = base_traction_limit
	
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
	
	apply_force(lat_force_vec + (forward_dir * drive_force_mag), wheel.global_position - global_position)

# ==============================================================================
# VISUALS
# ==============================================================================

func update_visuals(delta: float):
	var mesh_list = [mesh_fl, mesh_fr, mesh_rl, mesh_rr]
	
	for i in range(4):
		var mesh = mesh_list[i]
		var ray = wheels[i]
		
		if !mesh or !ray: continue
		
		mesh.transform = initial_transforms[i]
		
		var wheel_world_pos: Vector3
		var ray_basis = ray.global_transform.basis
		var ray_up = ray_basis.y
		
		if ray.is_colliding():
			var hit_point = ray.get_collision_point()
			wheel_world_pos = hit_point + (ray_up * wheel_radius)
		else:
			var rest_length = get_blended_rest_length(i)
			var hang_distance = rest_length - wheel_radius
			wheel_world_pos = ray.global_position - (ray_up * hang_distance)

		mesh.global_position = wheel_world_pos
		
		if i < 2: 
			mesh.rotate_object_local(Vector3.UP, current_steer_angle)
		
		var speed = linear_velocity.length()
		var forward_dot = linear_velocity.dot(-global_transform.basis.z)
		var dir = 1.0 if forward_dot > 0 else -1.0
		
		if ray.is_colliding():
			accumulated_spin[i] += speed * delta * dir * 0.1
		
		mesh.rotate_object_local(spin_axis, accumulated_spin[i])

# ==============================================================================
# HELPERS
# ==============================================================================

func get_pacejka_params(surface: String) -> Dictionary:
	if surface == "Gravel":
		return { "B": 5.0, "C": 2.0, "D": 1.2, "E": 0.2 }
	else:
		return { "B": 8.0, "C": 1.9, "D": 2.0, "E": -0.5 }

func pacejka_formula(slip: float, p: Dictionary) -> float:
	var x = slip * p.B
	return p.D * sin(p.C * atan(x - p.E * (x - atan(x))))

func calculate_awd_torque(index: int, total_drive: float) -> float:
	if index < 2: 
		return (total_drive * (1.0 - torque_split)) / 2.0 
	else: 
		return (total_drive * torque_split) / 2.0

func get_velocity_at_point(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - global_position)
