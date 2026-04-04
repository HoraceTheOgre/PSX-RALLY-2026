extends RigidBody3D

# RALLY CONTROLLER — MULTI-SURFACE VERSION
# Surfaces are defined in separate Resource files:

# To add a new surface:
#   1. Create a new script extending SurfaceData, set values in _init()
#   2. Add @export var my_surface: SurfaceData below
#   3. Add a group string to _get_surface_for_collider()

# --- Surface Resources ---
@export_group("Surfaces")
@export var gravel_surface: SurfaceData
@export var tarmac_surface: SurfaceData
@export var grass_surface:  SurfaceData

# --- Suspension Blending ---
@export_group("Suspension Adaptation")
@export var suspension_blend_speed: float = 2.0
@export var wheel_radius: float           = 0.3
@export var max_suspension_force: float   = 50000.0

# --- Anti-Pitch ---
@export_group("Anti-Pitch Control")
@export var enable_anti_pitch: bool       = true
@export var anti_pitch_strength: float    = 80000.0
@export var pitch_damping_strength: float = 40000.0

# --- Drivetrain ---
@export_group("Drivetrain")
@export var engine_power: float           = 20000.0
@export var power_curve_falloff: float    = 0.05
@export var top_speed_kph: float          = 220.0
@export var torque_split: float           = 0.5
@export var min_power_ratio: float        = 0.85

@export_subgroup("Dynamic Torque Split")
@export var enable_dynamic_torque: bool         = true
@export var low_speed_rear_split: float         = 0.35
@export var high_speed_rear_split: float        = 0.60
@export var torque_transition_speed_kph: float  = 60.0

# --- Braking & Resistance ---
@export_group("Braking & Resistance")
@export var brake_force: float        = 8000.0
@export var handbrake_force: float    = 40000.0
@export var rolling_resistance: float = 15.0
@export var air_resistance: float     = 0.2

# --- Steering ---
@export_group("Steering")
@export var max_steer_angle: float = 0.55
@export var steer_speed: float     = 1.0

@export_subgroup("Low-Speed Steering")
@export var low_speed_steer_reduction_enabled: bool = true
@export var low_speed_min_kph: float                = 10.0
@export var low_speed_max_kph: float                = 40.0
@export var min_low_speed_steer_ratio: float        = 0.5

@export_subgroup("High-Speed Steering")
@export var high_speed_reduction_start_kph: float = 60.0
@export var high_speed_reduction_end_kph: float   = 140.0
@export var min_high_speed_steer_ratio: float     = 0.35
@export var reduce_lateral_grip_with_speed: bool  = true

# --- Traction ---
@export_group("Traction Circle Override")
@export var longitudinal_grip_multiplier: float = 4.0
@export var straight_line_slip_angle: float     = 0.15

# --- Grip Recovery ---
@export_group("Grip Recovery")
@export var gravel_grip_recovery_speed: float = 2.0
@export var slide_drag_slip_threshold: float  = 5.0

# --- Speed Boost ---
@export_group("Speed Boost")
@export var speed_boost_min_kph: float = 20.0

# --- Debug ---
@export_group("Debug Settings")
@export var enable_detailed_debug: bool = true
@export var debug_interval: float       = 0.5
@export var debug_min_speed: float      = 20.0
@export var debug_max_speed: float      = 100.0
@export var debug_throttle_threshold: float = 0.5

# --- Visuals ---
@export_group("Visuals")
@export var mesh_fl: Node3D
@export var mesh_fr: Node3D
@export var mesh_rl: Node3D
@export var mesh_rr: Node3D
@export var spin_axis: Vector3 = Vector3.UP

# ==============================================================================
# INTERNAL STATE
# ==============================================================================

@onready var wheels: Array = [
	$WheelContainer/FL,
	$WheelContainer/FR,
	$WheelContainer/RL,
	$WheelContainer/RR
]

var prev_compression: Array[float]  = [0.0, 0.0, 0.0, 0.0]
var prev_length: Array[float]       = [0.6, 0.6, 0.6, 0.6]
var current_steer_angle: float      = 0.0
var initial_transforms: Array[Transform3D]
var accumulated_spin: Array[float]  = [0.0, 0.0, 0.0, 0.0]
var input_blocked: bool = false

# Per-wheel surface tracking
var wheel_surfaces: Array[String]      = ["Tarmac", "Tarmac", "Tarmac", "Tarmac"]
var prev_wheel_surfaces: Array[String] = ["Tarmac", "Tarmac", "Tarmac", "Tarmac"]

# Per-wheel blend: 0.0 = at source surface, 1.0 = at target surface
var suspension_blend: Array[float]         = [1.0, 1.0, 1.0, 1.0]
var wheel_source_surface: Array            = []   # SurfaceData — where we're blending FROM
var wheel_target_surface: Array            = []   # SurfaceData — where we're blending TO

var straight_accel_timer: float            = 0.0
var front_grip_modifier: Array[float]      = [1.0, 1.0]

# Debug data
var total_drive_force: float               = 0.0
var total_lat_force: float                 = 0.0
var is_handbrake_active: bool              = false
var wheel_slip_angles: Array[float]        = [0.0, 0.0, 0.0, 0.0]
var wheel_normal_loads: Array[float]       = [0.0, 0.0, 0.0, 0.0]
var wheel_drive_forces: Array[float]       = [0.0, 0.0, 0.0, 0.0]
var wheel_lateral_forces: Array[float]     = [0.0, 0.0, 0.0, 0.0]
var wheel_traction_limits: Array[float]    = [0.0, 0.0, 0.0, 0.0]
var body_slip_angle: float                 = 0.0
var yaw_rate: float                        = 0.0
var debug_timer: float                     = 0.0

# ==============================================================================
# READY
# ==============================================================================

func _ready() -> void:
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.45, -0.25)

	wheels[1].position.x = -wheels[0].position.x
	wheels[3].position.x = -wheels[2].position.x
	wheels[1].position.z =  wheels[0].position.z
	wheels[3].position.z =  wheels[2].position.z
	
	wheels[1].position.y = wheels[0].position.y
	wheels[3].position.y = wheels[2].position.y

	var mesh_list = [mesh_fl, mesh_fr, mesh_rl, mesh_rr]
	for mesh in mesh_list:
		initial_transforms.append(mesh.transform if mesh else Transform3D())

	# Fallback: if no surface assigned in Inspector, create defaults
	if not gravel_surface: gravel_surface = GravelSurface.new()
	if not tarmac_surface: tarmac_surface = TarmacSurface.new()
	if not grass_surface:  grass_surface  = GrassSurface.new()

	# All wheels start on tarmac by convention; detect_surfaces() will correct this
	for i in range(4):
		wheel_source_surface.append(tarmac_surface)
		wheel_target_surface.append(tarmac_surface)

# ==============================================================================
# PHYSICS LOOP
# ==============================================================================

func _physics_process(delta: float) -> void:
	var throttle        = Input.get_action_strength("accelerate") if not input_blocked else 0.0
	var brake           = Input.get_action_strength("brake")      if not input_blocked else 0.0
	var steer_input     = Input.get_axis("steer_right", "steer_left") if not input_blocked else 0.0
	is_handbrake_active = Input.is_action_pressed("handbrake")    and not input_blocked

	var speed_kph    = linear_velocity.length() * 3.6
	var forward_dot  = linear_velocity.dot(-global_transform.basis.z)
	var is_reversing = false

	if brake > 0.1 and throttle < 0.1:
		if speed_kph < 5.0 or forward_dot < -0.5:
			throttle     = brake
			brake        = 0.0
			is_reversing = true

	var steer_multiplier = calculate_combined_steer_multiplier(speed_kph)
	var target_angle     = steer_input * max_steer_angle * steer_multiplier

	# Steer rate: how fast the wheels physically reach the target angle.
	#   0-30  km/h: 6.0-5.0  (fast and sharp — easy to place the car in tight sections)
	#   30-80 km/h: 5.0-3.0  (calm mid-speed band)
	#   80+   km/h: 3.0-5.0  (quicker again for high-speed micro-corrections)
	var effective_steer_speed: float
	if speed_kph < 30.0:
		effective_steer_speed = lerp(6.0, 5.0, clamp(speed_kph / 30.0, 0.0, 1.0))
	elif speed_kph < 80.0:
		effective_steer_speed = lerp(5.0, 3.0, clamp((speed_kph - 30.0) / 50.0, 0.0, 1.0))
	else:
		effective_steer_speed = lerp(3.0, 5.0, clamp((speed_kph - 80.0) / 60.0, 0.0, 1.0))
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
	apply_surface_speed_penalty()

	if enable_anti_pitch:
		apply_anti_pitch_control()

	apply_resistance_forces()

	total_drive_force = 0.0
	total_lat_force   = 0.0

	if linear_velocity.length() > 1.0:
		var forward_dir   = -global_transform.basis.z
		var velocity_dir  = linear_velocity.normalized()
		var lateral_dir   = global_transform.basis.x
		body_slip_angle   = atan2(velocity_dir.dot(lateral_dir), velocity_dir.dot(forward_dir))
	else:
		body_slip_angle = 0.0

	yaw_rate = angular_velocity.dot(global_transform.basis.y)

	for i in range(wheels.size()):
		var wheel = wheels[i]
		if wheel.is_colliding():
			apply_suspension_force(wheel, i, delta)
			apply_tire_force(wheel, i, throttle, brake, delta, steer_multiplier, is_reversing)
		else:
			prev_compression[i]      = 0.0
			prev_length[i]           = _blended_param(i, "rest_length")
			wheel_slip_angles[i]     = 0.0
			wheel_normal_loads[i]    = 0.0
			wheel_drive_forces[i]    = 0.0
			wheel_lateral_forces[i]  = 0.0

	apply_arb(0, 1, _blended_param_avg([0, 1], "arb_stiffness_front"))
	apply_arb(2, 3, _blended_param_avg([2, 3], "arb_stiffness_rear"))

	update_visuals(delta)

	debug_timer += delta
	if enable_detailed_debug and debug_timer >= debug_interval:
		if throttle > debug_throttle_threshold or brake > 0.5:
			if speed_kph >= debug_min_speed and speed_kph <= debug_max_speed:
				##print_detailed_debug(speed_kph, throttle, steer_input)
				debug_timer = 0.0

# ==============================================================================
# SURFACE DETECTION
# ==============================================================================

## Maps a physics collider to the correct SurfaceData resource.
## Add new surfaces here — just check for the collider's group name.
func _get_surface_for_collider(collider: Object) -> Array:  # [SurfaceData, String]
	if collider == null:
		return [tarmac_surface, "Tarmac"]
	if collider.is_in_group("Gravel"):
		return [gravel_surface, "Gravel"]
	if collider.is_in_group("Grass"):
		return [grass_surface, "Grass"]
	# Default: treat everything else as tarmac
	return [tarmac_surface, "Tarmac"]

func detect_surfaces(delta: float) -> void:
	for i in range(wheels.size()):
		var wheel = wheels[i]
		if not wheel.is_colliding():
			# Keep blending toward last known target while airborne
			suspension_blend[i] = lerp(suspension_blend[i], 1.0, suspension_blend_speed * delta)
			continue

		var result         = _get_surface_for_collider(wheel.get_collider())
		var new_data: SurfaceData = result[0]
		var new_name: String      = result[1]

		if new_data != wheel_target_surface[i]:
			# Surface changed — capture current blend state as new source, reset blend
			var current_blend = suspension_blend[i]
			wheel_source_surface[i] = wheel_source_surface[i].lerp_with(
				wheel_target_surface[i], current_blend)
			wheel_target_surface[i] = new_data
			suspension_blend[i]     = 0.0

			if new_name != wheel_surfaces[i]:
				var wheel_names = ["FL", "FR", "RL", "RR"]
				print("🏁 %s: %s → %s" % [wheel_names[i], wheel_surfaces[i], new_name])
			wheel_surfaces[i]      = new_name
			prev_wheel_surfaces[i] = new_name
		else:
			suspension_blend[i] = lerp(suspension_blend[i], 1.0, suspension_blend_speed * delta)

# ==============================================================================
# SURFACE PARAMETER HELPERS
# ==============================================================================

## Blends a named float property between source and target for wheel [index].
func _blended_param(index: int, param: StringName) -> float:
	var src = wheel_source_surface[index]
	var tgt = wheel_target_surface[index]
	return lerp(src.get(param) as float, tgt.get(param) as float, suspension_blend[index])

## Returns the average of a blended param across multiple wheel indices.
func _blended_param_avg(indices: Array, param: StringName) -> float:
	var total := 0.0
	for i in indices:
		total += _blended_param(i, param)
	return total / indices.size()

func get_blended_suspension_params(index: int) -> Dictionary:
	return {
		"spring_stiffness":        _blended_param(index, "spring_stiffness"),
		"spring_progressive_rate": _blended_param(index, "spring_progressive_rate"),
		"damping_compression":     _blended_param(index, "damping_compression"),
		"damping_rebound":         _blended_param(index, "damping_rebound"),
		"rest_length":             _blended_param(index, "rest_length"),
		"max_compression":         _blended_param(index, "max_compression"),
		"bump_stop_stiffness":     _blended_param(index, "bump_stop_stiffness"),
	}

# ==============================================================================
# SUSPENSION FORCE
# ==============================================================================

func apply_suspension_force(wheel: RayCast3D, index: int, delta: float) -> void:
	var params        = get_blended_suspension_params(index)
	var contact_point = wheel.get_collision_point()
	var dist          = wheel.global_position.distance_to(contact_point)
	var current_length = clamp(dist, 0.0, params.rest_length)
	var compression    = params.rest_length - current_length

	var compression_ratio      = compression / params.rest_length
	var progressive_multiplier = 1.0 + (compression_ratio * compression_ratio * params.spring_progressive_rate)
	var spring_force           = compression * params.spring_stiffness * progressive_multiplier

	if compression > params.max_compression:
		spring_force += (compression - params.max_compression) * params.bump_stop_stiffness

	var suspension_velocity = (current_length - prev_length[index]) / delta
	var damper_force: float
	if suspension_velocity < 0:
		damper_force = -suspension_velocity * params.damping_compression
	else:
		var rebound_multiplier = 1.0
		if compression_ratio > 0.5:
			rebound_multiplier = clamp(1.0 - ((compression_ratio - 0.5) * 1.0), 0.5, 1.0)
		damper_force = -suspension_velocity * params.damping_rebound * rebound_multiplier

	var total_force  = clamp(spring_force + damper_force, 0.0, max_suspension_force)
	var force_vector = wheel.get_collision_normal() * total_force
	apply_force(force_vector, wheel.global_position - global_position)

	prev_compression[index] = compression
	prev_length[index]      = current_length

# ==============================================================================
# TIRE FORCE
# ==============================================================================

func apply_tire_force(wheel: RayCast3D, index: int, throttle: float, brake: float,
		delta: float, steer_multiplier: float, is_reversing: bool = false) -> void:

	var src: SurfaceData = wheel_source_surface[index]
	var tgt: SurfaceData = wheel_target_surface[index]
	var bl: float        = suspension_blend[index]

	# Blended tire params
	var is_rear    = index >= 2
	var tire_params = _lerp_pacejka(src.get_pacejka(is_rear), tgt.get_pacejka(is_rear), bl)

	var wheel_basis = wheel.global_transform.basis
	if index < 2:
		wheel_basis = wheel_basis.rotated(wheel.global_transform.basis.y, current_steer_angle)

	var forward_dir = -wheel_basis.z
	var right_dir   = wheel_basis.x
	var wheel_vel   = get_velocity_at_point(wheel.get_collision_point())
	var v_long      = forward_dir.dot(wheel_vel)
	var v_lat       = right_dir.dot(wheel_vel)
	var speed       = wheel_vel.length()
	var slip_angle  = atan2(v_lat, max(abs(v_long), 0.5))

	if speed < 2.0:
		slip_angle *= speed / 2.0

	wheel_slip_angles[index] = slip_angle

	# Normal load
	var base_load   = (mass / 4.0) * 9.8
	var params      = get_blended_suspension_params(index)
	var normal_load = max(base_load + prev_compression[index] * params.spring_stiffness * 0.5, 100.0)
	wheel_normal_loads[index] = normal_load

	var optimal_load     = base_load * 1.2
	var load_sensitivity = clamp(optimal_load / normal_load, 0.7, 1.0) if normal_load > optimal_load else 1.0

	# --- Lateral Force ---
	var lateral_coeff = pacejka_formula(slip_angle, tire_params)
	var lat_force_mag = lateral_coeff * normal_load * load_sensitivity

	var surface_grip     = lerp(src.lateral_grip_multiplier, tgt.lateral_grip_multiplier, bl)
	lat_force_mag       *= surface_grip

	var car_speed_ms         = linear_velocity.length()
	var low_speed_lat_scale  = clamp(car_speed_ms / 8.5, 0.6, 1.0)
	if not is_reversing:
		lat_force_mag *= low_speed_lat_scale

	if reduce_lateral_grip_with_speed:
		lat_force_mag *= steer_multiplier

	if is_handbrake_active and index >= 2:
		# Near-zero rear lateral grip: rear breaks free immediately and rotates freely
		lat_force_mag *= 0.05

	var lat_force_vec = -right_dir * lat_force_mag
	total_lat_force  += abs(lat_force_mag)
	wheel_lateral_forces[index] = abs(lat_force_mag)

	# --- Countersteer Grip Penalty (front only) ---
	if index < 2:
		var body_slip_deg  = rad_to_deg(abs(body_slip_angle))
		var threshold      = lerp(src.slide_threshold_deg, tgt.slide_threshold_deg, bl)
		var penalty_target = lerp(src.countersteer_grip_penalty, tgt.countersteer_grip_penalty, bl)
		var target_grip    = 1.0

		if body_slip_deg > threshold:
			var slide_severity = clamp((body_slip_deg - threshold) / 15.0, 0.0, 1.0)
			target_grip        = lerp(1.0, penalty_target, slide_severity)

		if target_grip < front_grip_modifier[index]:
			front_grip_modifier[index] = target_grip
		else:
			front_grip_modifier[index] = lerp(front_grip_modifier[index], target_grip,
				gravel_grip_recovery_speed * delta)

		lat_force_mag *= front_grip_modifier[index]

	# --- Slide Drag ---
	# Suppressed on rear wheels during handbrake — locked rear wheels naturally hit ~90 deg slip
	# which would apply maximum drag every frame and kill all momentum. The rotation itself
	# (lateral force = 0.05) is what slows the rear, not surface drag.
	var slip_deg = rad_to_deg(abs(slip_angle))
	var is_handbrake_rear = is_handbrake_active and index >= 2
	if slip_deg > slide_drag_slip_threshold and not is_handbrake_rear:
		var drag_factor  = pow(clamp((slip_deg - slide_drag_slip_threshold) / 25.0, 0.0, 1.0), 2.0)
		var surface_drag = lerp(src.slide_drag, tgt.slide_drag, bl)
		var velocity_dir = wheel_vel.normalized()
		if velocity_dir.length() > 0.1:
			apply_force(-velocity_dir * drag_factor * surface_drag * (normal_load / 5000.0),
				wheel.global_position - global_position)

	# --- Longitudinal Force ---
	var drive_force_mag = 0.0
	var is_braking      = false

	if is_handbrake_active and index >= 2:
		var brake_dir   = -1.0 if v_long > 0 else 1.0
		drive_force_mag = brake_dir * handbrake_force
		is_braking      = true
		total_drive_force += abs(drive_force_mag)

	elif brake > 0.01:
		var brake_dir   = -1.0 if v_long > 0 else 1.0
		var brake_bias  = 0.6 if index < 2 else 0.4
		var brake_mult  = lerp(src.brake_multiplier, tgt.brake_multiplier, bl)
		drive_force_mag = brake_dir * brake_force * brake * brake_bias * 2.5 * brake_mult
		is_braking      = true
		total_drive_force += abs(drive_force_mag)

	elif throttle > 0.01:
		var car_speed      = linear_velocity.length()
		var top_speed_mult = lerp(src.top_speed_multiplier, tgt.top_speed_multiplier, bl)
		var power_mult     = lerp(src.power_multiplier,     tgt.power_multiplier,     bl)

		# Reverse is capped at 40 km/h regardless of surface
		var effective_top_speed = top_speed_kph * top_speed_mult if not is_reversing else 40.0
		var top_speed_ms   = effective_top_speed / 3.6
		var speed_ratio    = clamp(car_speed / top_speed_ms, 0.0, 1.0)
		var power_ratio    = max(1.0 - speed_ratio * power_curve_falloff, min_power_ratio)
		var total_drive    = engine_power * throttle * power_ratio * power_mult

		if not is_reversing and index >= 2 and abs(body_slip_angle) > 0.26:
			var slide_red = clamp(1.0 - (abs(body_slip_angle) - 0.26) * 1.5, 0.5, 1.0)
			total_drive  *= slide_red

		drive_force_mag = calculate_awd_torque(index, total_drive)
		# Flip direction when reversing — without this the force always pushes forward
		if is_reversing:
			drive_force_mag = -drive_force_mag
		total_drive_force += drive_force_mag

	wheel_drive_forces[index] = abs(drive_force_mag)

	# --- Traction Circle ---
	var slip_angle_abs      = abs(slip_angle)
	var base_traction_limit = tire_params.D * normal_load * load_sensitivity
	var longitudinal_limit: float
	if slip_angle_abs < straight_line_slip_angle:
		var straight_factor  = 1.0 - (slip_angle_abs / straight_line_slip_angle)
		longitudinal_limit   = base_traction_limit * (1.0 + (longitudinal_grip_multiplier - 1.0) * straight_factor)
	else:
		longitudinal_limit = base_traction_limit

	wheel_traction_limits[index] = longitudinal_limit
	var lateral_limit = base_traction_limit

	if abs(drive_force_mag) > longitudinal_limit or abs(lat_force_mag) > lateral_limit:
		if is_handbrake_active and index >= 2:
			# High longitudinal cap: lets the locking force fully overwhelm rear grip -> spin
			# Very low lateral cap: rear has almost no sideways resistance -> rotates freely
			drive_force_mag = clamp(drive_force_mag, -longitudinal_limit * 3.0,  longitudinal_limit * 3.0)
			lat_force_mag   = clamp(lat_force_mag,   -lateral_limit      * 0.05, lateral_limit      * 0.05)
		elif is_braking:
			drive_force_mag = clamp(drive_force_mag, -longitudinal_limit * 0.9,  longitudinal_limit * 0.9)
			lat_force_mag   = clamp(lat_force_mag,   -lateral_limit,             lateral_limit)
		else:
			drive_force_mag = clamp(drive_force_mag, -longitudinal_limit,        longitudinal_limit)
			lat_force_mag   = clamp(lat_force_mag,   -lateral_limit,             lateral_limit)
		lat_force_vec = -right_dir * lat_force_mag

	var force_point = wheel.global_position - global_position
	if is_braking and not is_handbrake_active:
		apply_force(lat_force_vec, force_point)
		var brake_point   = force_point
		brake_point.y     = center_of_mass.y
		apply_force(forward_dir * drive_force_mag, brake_point)
	else:
		apply_force(lat_force_vec + (forward_dir * drive_force_mag), force_point)

# ==============================================================================
# STEERING
# ==============================================================================

func calculate_combined_steer_multiplier(speed_kph: float) -> float:
	# Multiplier curve (angle reduction only, rate handled separately):
	#   0      km/h  ->  0.15   (near-stationary floor)
	#   0-30   km/h  ->  ramp up to 0.70
	#   30-40  km/h  ->  plateau at 0.70  (peak — less twitchy than the old 1.0)
	#   40-120 km/h  ->  ramp down to 0.08
	var low_speed_floor      = 0.55   # Was 0.15 — much more angle available from standstill
	var peak_multiplier      = 0.90   # Was 0.70 — nearly full lock at low speed
	var peak_speed           = 30.0
	var plateau_end          = 40.0
	var high_speed_floor     = 0.08
	var full_reduction_speed = 120.0

	if speed_kph <= 0.0:
		return low_speed_floor
	elif speed_kph < peak_speed:
		var f = speed_kph / peak_speed
		f = f * f * (3.0 - 2.0 * f)
		return lerp(low_speed_floor, peak_multiplier, f)
	elif speed_kph <= plateau_end:
		return peak_multiplier
	elif speed_kph >= full_reduction_speed:
		return high_speed_floor
	else:
		var f = (speed_kph - plateau_end) / (full_reduction_speed - plateau_end)
		f = f * f * (3.0 - 2.0 * f)
		return lerp(peak_multiplier, high_speed_floor, f)

# ==============================================================================
# STABILITY & HANDLING HELPERS
# ==============================================================================

func apply_anti_pitch_control() -> void:
	var throttle    = Input.get_action_strength("accelerate")
	var brake       = Input.get_action_strength("brake")
	var speed_kph   = linear_velocity.length() * 3.6
	var forward_dot = linear_velocity.dot(-global_transform.basis.z)

	if brake > 0.1 and throttle < 0.1 and (speed_kph < 5.0 or forward_dot < -0.5):
		return
	if speed_kph < 5.0:
		return

	var front_comp    = (prev_compression[0] + prev_compression[1]) * 0.5
	var rear_comp     = (prev_compression[2] + prev_compression[3]) * 0.5
	var comp_diff     = front_comp - rear_comp

	if brake > 0.1:
		var target_diff = 0.06
		var error       = target_diff - comp_diff
		if error > 0.0:
			var correction = min(error * 600000.0 * brake, 35000.0)
			for i in [0, 1]:
				if wheels[i].is_colliding():
					apply_force(Vector3.DOWN * correction,  wheels[i].global_position - global_position)
			for i in [2, 3]:
				if wheels[i].is_colliding():
					apply_force(Vector3.UP   * correction,  wheels[i].global_position - global_position)
	elif throttle > 0.1 and brake < 0.1:
		var speed_factor = clamp(speed_kph / 80.0, 0.0, 1.0)
		var rear_help    = throttle * speed_factor * 3000.0
		for i in [2, 3]:
			if wheels[i].is_colliding():
				apply_force(Vector3.DOWN * rear_help, wheels[i].global_position - global_position)

	apply_torque(-global_transform.basis.x * angular_velocity.dot(global_transform.basis.x) * pitch_damping_strength)

func apply_rear_downforce() -> void:
	if Input.get_action_strength("brake") > 0.1:
		return
	var rear_compression = (prev_compression[2] + prev_compression[3]) * 0.5
	if rear_compression < 0.020:
		for i in [2, 3]:
			apply_force(Vector3.DOWN * 15000.0, wheels[i].global_position - global_position)

func apply_yaw_damping() -> void:
	var speed_kph = linear_velocity.length() * 3.6
	if speed_kph < 5.0 or speed_kph > 80.0:
		return
	var yaw_velocity = angular_velocity.dot(global_transform.basis.y)
	if abs(yaw_velocity) > 1.5:
		apply_torque(-global_transform.basis.y * yaw_velocity * 8000.0)

func apply_resistance_forces() -> void:
	var speed = linear_velocity.length()
	if speed < 0.1:
		return
	var dir = linear_velocity.normalized()
	apply_central_force(dir * (-rolling_resistance - air_resistance * speed * speed))

func apply_surface_speed_penalty() -> void:
	var speed = linear_velocity.length()
	if speed < 1.0:
		return
	var drag = _blended_param_avg([0, 1, 2, 3], "speed_drag")
	apply_central_force(-linear_velocity.normalized() * drag * speed * speed / 1000.0)

func apply_straight_line_assist() -> void:
	var throttle    = Input.get_action_strength("accelerate")
	var steer_input = abs(Input.get_axis("steer_right", "steer_left"))
	var speed_kph   = linear_velocity.length() * 3.6

	if throttle > 0.5 and steer_input < 0.1 and speed_kph > 5.0:
		straight_accel_timer += get_physics_process_delta_time()
	else:
		straight_accel_timer = 0.0
		return

	var activation_delay: float
	if speed_kph < 15.0:
		activation_delay = 1.5
	elif speed_kph > 40.0:
		activation_delay = 0.5
	else:
		activation_delay = lerp(2.5, 1.5, (speed_kph - 15.0) / 25.0)

	if straight_accel_timer < activation_delay:
		return

	var ramp_factor = pow(clamp((straight_accel_timer - activation_delay) / 2.0, 0.0, 1.0), 2.0)
	var lateral_dir     = global_transform.basis.x
	var lateral_velocity = linear_velocity.dot(lateral_dir)
	if abs(lateral_velocity) < 0.1:
		return
	apply_central_force(-lateral_dir * lateral_velocity * mass * 1.0 * ramp_factor)

	var yaw_velocity = angular_velocity.dot(global_transform.basis.y)
	if abs(yaw_velocity) > 0.02:
		apply_torque(-global_transform.basis.y * yaw_velocity * 8000.0 * ramp_factor)

func apply_slide_recovery() -> void:
	var speed_kph = linear_velocity.length() * 3.6
	if speed_kph < 30.0 or abs(Input.get_axis("steer_right", "steer_left")) > 0.1:
		return
	if linear_velocity.length() > 5.0:
		var forward_dir   = -global_transform.basis.z
		var velocity_dir  = linear_velocity.normalized()
		var lateral_dir   = global_transform.basis.x
		var current_slip  = atan2(velocity_dir.dot(lateral_dir), velocity_dir.dot(forward_dir))
		if abs(current_slip) > 0.26:
			var yaw_velocity   = angular_velocity.dot(global_transform.basis.y)
			apply_torque(-global_transform.basis.y * yaw_velocity * 12000.0 * abs(current_slip))

func apply_active_anti_roll() -> void:
	var right_vector = global_transform.basis.x
	var roll_angle   = right_vector.dot(Vector3.UP)
	if abs(roll_angle) > 0.08:
		var strength = 20000.0 * abs(roll_angle)
		var axis     = -global_transform.basis.z
		apply_torque(axis * (-strength if roll_angle > 0 else strength))

	var brake = Input.get_action_strength("brake")
	for i in range(4):
		if wheels[i].is_colliding():
			if brake > 0.1 and i >= 2:
				continue
			if wheel_normal_loads[i] < 5500.0:
				var deficit = 5500.0 - wheel_normal_loads[i]
				apply_force(Vector3.DOWN * deficit * 3.0, wheels[i].global_position - global_position)
		else:
			apply_force(Vector3.DOWN * 15000.0, wheels[i].global_position - global_position)

	if abs(current_steer_angle) > 0.25:
		var turn_dir       = sign(current_steer_angle)
		var outside_idx    = [0, 2] if turn_dir > 0 else [1, 3]
		var inside_idx     = [1, 3] if turn_dir > 0 else [0, 2]
		var outside_load   = wheel_normal_loads[outside_idx[0]] + wheel_normal_loads[outside_idx[1]]
		var inside_load    = wheel_normal_loads[inside_idx[0]]  + wheel_normal_loads[inside_idx[1]]
		var total_load     = outside_load + inside_load
		if total_load > 100:
			var inside_ratio = inside_load / total_load
			if inside_ratio < 0.48:
				var transfer = 28000.0 * (0.48 - inside_ratio)
				for idx in inside_idx:
					apply_force(Vector3.DOWN * transfer, wheels[idx].global_position - global_position)

func apply_anti_rollover_force() -> void:
	var up_vector = global_transform.basis.y
	var roll_angle = up_vector.angle_to(Vector3.UP)
	if roll_angle > 0.3:
		var roll_axis      = up_vector.cross(Vector3.UP).normalized()
		var strength       = min((roll_angle - 0.3) * 20000.0, 30000.0)
		apply_torque(roll_axis * strength)
		var right_vector   = global_transform.basis.x
		var roll_direction = sign(right_vector.dot(Vector3.UP))
		for i in range(4):
			var is_right = (i == 1 or i == 3)
			if wheels[i].is_colliding():
				if (is_right and roll_direction < 0) or (not is_right and roll_direction > 0):
					apply_force(Vector3.DOWN * strength * 0.3, wheels[i].global_position - global_position)

func apply_arb(left_idx: int, right_idx: int, stiffness: float) -> void:
	var w_l = wheels[left_idx]
	var w_r = wheels[right_idx]
	if not (w_l.is_colliding() and w_r.is_colliding()):
		return
	var comp_diff         = prev_compression[left_idx] - prev_compression[right_idx]
	var max_comp          = max(prev_compression[left_idx], prev_compression[right_idx])
	var avg_rest          = (_blended_param(left_idx, "rest_length") + _blended_param(right_idx, "rest_length")) * 0.5
	var compression_ratio = max_comp / avg_rest
	var arb_reduction     = clamp(1.0 - compression_ratio * compression_ratio * 0.7, 0.3, 1.0)
	var arb_force         = comp_diff * stiffness * arb_reduction
	apply_force(w_l.get_collision_normal() * -arb_force, w_l.global_position - global_position)
	apply_force(w_r.get_collision_normal() *  arb_force, w_r.global_position - global_position)

# ==============================================================================
# DRIVETRAIN HELPERS
# ==============================================================================

func calculate_awd_torque(index: int, total_drive: float) -> float:
	var split = calculate_dynamic_torque_split(linear_velocity.length() * 3.6)
	return (total_drive * (1.0 - split if index < 2 else split)) / 2.0

func calculate_dynamic_torque_split(speed_kph: float) -> float:
	if not enable_dynamic_torque:
		return torque_split
	if speed_kph <= 0.0:
		return low_speed_rear_split
	if speed_kph >= torque_transition_speed_kph:
		return high_speed_rear_split
	var f = speed_kph / torque_transition_speed_kph
	f = f * f * (3.0 - 2.0 * f)
	return lerp(low_speed_rear_split, high_speed_rear_split, f)

func get_velocity_at_point(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - global_position)

# ==============================================================================
# PACEJKA
# ==============================================================================

func pacejka_formula(slip: float, p: Dictionary) -> float:
	var x = slip * p.B
	return p.D * sin(p.C * atan(x - p.E * (x - atan(x))))

## Linearly interpolates two Pacejka parameter dicts by [t].
func _lerp_pacejka(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"B": lerp(a.B, b.B, t),
		"C": lerp(a.C, b.C, t),
		"D": lerp(a.D, b.D, t),
		"E": lerp(a.E, b.E, t),
	}

# ==============================================================================
# VISUALS
# ==============================================================================

func update_visuals(delta: float) -> void:
	var mesh_list = [mesh_fl, mesh_fr, mesh_rl, mesh_rr]
	for i in range(4):
		var mesh = mesh_list[i]
		var ray  = wheels[i]
		if not mesh or not ray:
			continue

		mesh.transform = initial_transforms[i]

		var params       = get_blended_suspension_params(i)
		var current_dist = _blended_param(i, "rest_length")
		if ray.is_colliding():
			var hit_point    = ray.get_collision_point()
			current_dist     = ray.global_position.distance_to(hit_point)
			var max_vis_comp = params.rest_length - params.max_compression
			current_dist     = max(current_dist, max_vis_comp)

		mesh.position.y = initial_transforms[i].origin.y - (current_dist - wheel_radius)

		if i < 2:
			mesh.rotate_object_local(Vector3.UP, current_steer_angle)

		var forward_dot = linear_velocity.dot(-global_transform.basis.z)
		var dir         = 1.0 if forward_dot > 0 else -1.0
		if ray.is_colliding():
			accumulated_spin[i] += linear_velocity.length() * delta * dir * 0.1
		mesh.rotate_object_local(spin_axis, accumulated_spin[i])

# ==============================================================================
# DEBUG
# ==============================================================================

func print_detailed_debug(speed_kph: float, throttle: float, steer_input: float) -> void:
	var front_load      = wheel_normal_loads[0] + wheel_normal_loads[1]
	var rear_load       = wheel_normal_loads[2] + wheel_normal_loads[3]
	var total_load      = front_load + rear_load
	var front_comp      = (prev_compression[0] + prev_compression[1]) * 0.5
	var rear_comp       = (prev_compression[2] + prev_compression[3]) * 0.5
	var front_drive     = wheel_drive_forces[0] + wheel_drive_forces[1]
	var rear_drive      = wheel_drive_forces[2] + wheel_drive_forces[3]

	var surface_label = "[%s|%s|%s|%s]" % [
		wheel_surfaces[0], wheel_surfaces[1], wheel_surfaces[2], wheel_surfaces[3]]

	print("\n╔════════════════════════════════════════════╗")
	print("║     RALLY CAR DEBUG - %.1f km/h          ║" % speed_kph)
	print("║     Surfaces: %-28s ║" % surface_label)
	print("╠════════════════════════════════════════════╣")
	print("║ INPUTS                                     ║")
	print("║  Throttle: %.0f%%  |  Steering: %.2f      ║" % [throttle * 100, steer_input])
	print("║  Steer Angle: %.2f rad (%.0f°)            ║" % [current_steer_angle, rad_to_deg(current_steer_angle)])
	print("╠════════════════════════════════════════════╣")
	print("║ VEHICLE DYNAMICS                           ║")
	print("║  Body Slip: %.2f rad (%.1f°)              ║" % [body_slip_angle, rad_to_deg(body_slip_angle)])
	print("║  Yaw Rate:  %.2f rad/s                    ║" % yaw_rate)
	print("╠════════════════════════════════════════════╣")
	print("║ WEIGHT DISTRIBUTION                        ║")
	print("║  Front: %.0fN (%.0f%%)                    ║" % [front_load, (front_load / total_load) * 100])
	print("║  Rear:  %.0fN (%.0f%%)                    ║" % [rear_load, (rear_load / total_load) * 100])
	print("║  F Comp: %.3fm  |  R Comp: %.3fm          ║" % [front_comp, rear_comp])
	print("╠════════════════════════════════════════════╣")
	print("║ POWER  (Front: %.0fN / Rear: %.0fN)       ║" % [front_drive, rear_drive])
	print("║  Total Drive Force: %.0fN                 ║" % total_drive_force)
	print("╠════════════════════════════════════════════╣")
	print("║ WHEEL DATA           Load  Drive  Slip°   ║")
	for i in range(4):
		var names = ["FL", "FR", "RL", "RR"]
		print("║  %s: %.0fN | %.0fN/%.0fN | %.1f°         ║" % [
			names[i], wheel_normal_loads[i],
			wheel_drive_forces[i], wheel_traction_limits[i],
			rad_to_deg(wheel_slip_angles[i])
		])
	print("╚════════════════════════════════════════════╝\n")
