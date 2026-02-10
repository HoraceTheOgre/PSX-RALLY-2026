extends RigidBody3D

# ==============================================================================
# RALLY CONTROLLER (FIXED: PROPER ACCELERATION & TOP SPEED)
# ==============================================================================

# --- Configuration: Suspension (Gravel) ---
@export_group("Suspension System - Gravel")
@export var spring_stiffness_gravel: float = 80000.0
@export var spring_progressive_rate_gravel: float = 1.5
@export var damping_compression_gravel: float = 8000.0
@export var damping_rebound_gravel: float = 7000.0
@export var rest_length_gravel: float = 0.6
@export var max_compression_gravel: float = 0.5
@export var bump_stop_stiffness_gravel: float = 100000.0
@export var arb_stiffness_front_gravel: float = 6000.0
@export var arb_stiffness_rear_gravel: float = 3000.0

# --- Configuration: Suspension (Tarmac) ---
@export_group("Suspension System - Tarmac")
@export var spring_stiffness_tarmac: float = 120000.0  # Stiffer for less body roll
@export var spring_progressive_rate_tarmac: float = 1.0  # Less progressive
@export var damping_compression_tarmac: float = 12000.0  # Higher damping
@export var damping_rebound_tarmac: float = 10000.0  # Higher damping
@export var rest_length_tarmac: float = 0.45  # Lower ride height
@export var max_compression_tarmac: float = 0.35  # Less travel
@export var bump_stop_stiffness_tarmac: float = 150000.0  # Harder bump stops
@export var arb_stiffness_front_tarmac: float = 15000.0  # Much stiffer ARB
@export var arb_stiffness_rear_tarmac: float = 12000.0  # Much stiffer ARB

# --- Configuration: Suspension Blending ---
@export_group("Suspension Adaptation")
@export var suspension_blend_speed: float = 2.0  # How fast to transition (seconds)
@export var wheel_radius: float = 0.35
@export var max_suspension_force: float = 50000.0

# --- Configuration: Drivetrain ---
@export_group("Drivetrain")
@export var engine_power: float = 50000.0
@export var power_curve_falloff: float = 0.3
@export var top_speed_kph: float = 220.0
@export var torque_split: float = 0.5

# --- Configuration: Steering ---
@export_group("Steering")
@export var max_steer_angle: float = 1.5
@export var steer_speed: float = 9.0 

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
var suspension_blend: Array[float] = [0.0, 0.0, 0.0, 0.0]  # 0.0 = gravel, 1.0 = tarmac

# Current blended suspension parameters
var current_spring_stiffness: float
var current_spring_progressive_rate: float
var current_damping_compression: float
var current_damping_rebound: float
var current_rest_length: float
var current_max_compression: float
var current_bump_stop_stiffness: float

# Debug
var total_drive_force: float = 0.0
var total_lat_force: float = 0.0

func _ready():
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.2, 0)
	
	var mesh_list = [mesh_fl, mesh_fr, mesh_rl, mesh_rr]
	for mesh in mesh_list:
		if mesh:
			initial_transforms.append(mesh.transform)
		else:
			initial_transforms.append(Transform3D())
	
	# Initialize with gravel settings
	current_spring_stiffness = spring_stiffness_gravel
	current_spring_progressive_rate = spring_progressive_rate_gravel
	current_damping_compression = damping_compression_gravel
	current_damping_rebound = damping_rebound_gravel
	current_rest_length = rest_length_gravel
	current_max_compression = max_compression_gravel
	current_bump_stop_stiffness = bump_stop_stiffness_gravel

# ==============================================================================
# PHYSICS LOOP
# ==============================================================================

func _physics_process(delta: float):
	var throttle = Input.get_axis("brake", "accelerate")
	var steer_input = Input.get_axis("steer_right", "steer_left")
	
	var target_angle = steer_input * max_steer_angle
	current_steer_angle = lerp(current_steer_angle, target_angle, steer_speed * delta)
	
	for wheel in wheels:
		wheel.force_raycast_update()
	
	# Detect surfaces and blend suspension
	detect_surfaces(delta)
	
	apply_anti_rollover_force()
	
	total_drive_force = 0.0
	total_lat_force = 0.0
	
	for i in range(wheels.size()):
		var wheel = wheels[i]
		if wheel.is_colliding():
			apply_suspension_force(wheel, i, delta)
			apply_tire_force(wheel, i, throttle, delta)
		else:
			prev_compression[i] = 0.0
			prev_length[i] = get_blended_rest_length(i)
	
	# Apply ARB with surface-specific stiffness
	var arb_front = lerp(arb_stiffness_front_gravel, arb_stiffness_front_tarmac, 
		(suspension_blend[0] + suspension_blend[1]) * 0.5)
	var arb_rear = lerp(arb_stiffness_rear_gravel, arb_stiffness_rear_tarmac, 
		(suspension_blend[2] + suspension_blend[3]) * 0.5)
	
	apply_arb(0, 1, arb_front)
	apply_arb(2, 3, arb_rear)
	
	update_visuals(delta)
	
	# Debug with surface info
	var speed_kph = linear_velocity.length() * 3.6
	var top_speed_ms = top_speed_kph / 3.6
	var speed_ratio = clamp(linear_velocity.length() / top_speed_ms, 0.0, 1.0)
	var power_mult = 1.0 - (speed_ratio * power_curve_falloff)
	
	var surface_debug = "Surfaces: [%s, %s, %s, %s]" % [
		wheel_surfaces[0].substr(0, 1),
		wheel_surfaces[1].substr(0, 1),
		wheel_surfaces[2].substr(0, 1),
		wheel_surfaces[3].substr(0, 1)
	]
	
	print("Speed: %.1f km/h | Power: %.2f | Drive: %.0f N | Lat: %.0f N | %s" % 
		[speed_kph, power_mult, total_drive_force, total_lat_force, surface_debug])

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
				target_blend = 0.0  # Full gravel
			else:
				wheel_surfaces[i] = "Tarmac"
				target_blend = 1.0  # Full tarmac
		else:
			# Keep current surface when airborne
			target_blend = suspension_blend[i]
		
		# Smooth blend
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
	
	var susp_dir = (wheel.global_position - contact_point).normalized()
	
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
		# Use per-wheel rest lengths
		var rest_l = get_blended_rest_length(left_idx)
		var rest_r = get_blended_rest_length(right_idx)
		
		var comp_diff = prev_compression[left_idx] - prev_compression[right_idx]
		
		var max_compression_side = max(prev_compression[left_idx], prev_compression[right_idx])
		var avg_rest = (rest_l + rest_r) * 0.5
		var compression_ratio = max_compression_side / avg_rest
		
		var arb_reduction = 1.0 - (compression_ratio * compression_ratio * 0.7)
		arb_reduction = clamp(arb_reduction, 0.3, 1.0)
		
		var arb_force = comp_diff * stiffness * arb_reduction
		
		var left_contact = w_l.get_collision_point()
		var right_contact = w_r.get_collision_point()
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

func apply_tire_force(wheel: RayCast3D, index: int, throttle: float, delta: float):
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
	var slip_angle = atan2(v_lat, abs(v_long) + 0.1)
	
	var base_load = (mass / 4.0) * 9.8
	var params = get_blended_suspension_params(index)
	var spring_load = prev_compression[index] * params.spring_stiffness
	var normal_load = max(spring_load + base_load * 0.2, base_load * 0.5)
	
	var load_sensitivity = 1.0
	var optimal_load = base_load * 1.2
	if normal_load > optimal_load:
		load_sensitivity = optimal_load / normal_load
		load_sensitivity = clamp(load_sensitivity, 0.7, 1.0)
	
	var lateral_coeff = pacejka_formula(slip_angle, tire_params)
	var lat_force_mag = lateral_coeff * normal_load * load_sensitivity
	var lat_force_vec = -right_dir * lat_force_mag
	
	total_lat_force += abs(lat_force_mag)
	
	var car_speed = linear_velocity.length()
	var drive_force_mag = 0.0
	
	if throttle != 0:
		var top_speed_ms = top_speed_kph / 3.6
		var speed_ratio = clamp(car_speed / top_speed_ms, 0.0, 1.0)
		
		var power_multiplier = 1.0 - (speed_ratio * power_curve_falloff)
		power_multiplier = max(power_multiplier, 0.5)
		
		var total_drive = engine_power * throttle * power_multiplier
		drive_force_mag = calculate_awd_torque(index, total_drive)
		
		if index >= 2:
			var slip_reduction = cos(slip_angle * 2.0)
			slip_reduction = clamp(slip_reduction, 0.3, 1.0)
			drive_force_mag *= slip_reduction
		
		total_drive_force += drive_force_mag
	
	var traction_limit = tire_params.D * normal_load * load_sensitivity
	var combined_force = sqrt(drive_force_mag * drive_force_mag + lat_force_mag * lat_force_mag)
	
	if combined_force > traction_limit:
		var scale = traction_limit / combined_force
		var lat_priority = 0.8
		var long_priority = 0.2
		
		lat_force_mag *= scale * (1.0 + lat_priority * 0.5)
		drive_force_mag *= scale * (1.0 - long_priority * 0.5)
		
		lat_force_mag = clamp(lat_force_mag, -traction_limit, traction_limit)
		drive_force_mag = clamp(drive_force_mag, -traction_limit, traction_limit)
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
