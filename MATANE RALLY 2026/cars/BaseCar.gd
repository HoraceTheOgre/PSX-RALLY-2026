extends RigidBody3D

# ==================================================
# TUNING — CORE VEHICLE
# ==================================================

@export var engine_force: float = 16000.0
@export var brake_force: float = 12000.0
@export var steer_strength: float = 0.8

# Grip per surface
@export var grip_tarmac: float = 1.0
@export var grip_dirt: float = 0.35

# Lateral force ceiling
@export var max_lateral_force: float = 5200.0

# Aero
@export var downforce: float = 40.0

# Fake axle offsets (meters)
@export var front_axle_offset: float = 1.2
@export var rear_axle_offset: float = -1.2

# ==================================================
# SUSPENSION (FAKE, ARCADE, CORRECT)
# ==================================================

@export var suspension_rest_length: float = 1.1
@export var suspension_stiffness: float = 15000
@export var suspension_damping: float = 100

# ==================================================
# INTERNAL STATE
# ==================================================

var surface_grip_mul: float = 1.0
var throttle: float = 0.0
var steer_input: float = 0.0

@onready var ground_ray: RayCast3D = $GroundRay

# ==================================================
# PHYSICS LOOP
# ==================================================

func _physics_process(delta: float) -> void:
	update_inputs()
	update_surface()
	apply_suspension()
	apply_engine_force()
	apply_lateral_forces()
	apply_downforce()

# ==================================================
# INPUT
# ==================================================

func update_inputs() -> void:
	throttle = (
		Input.get_action_strength("accelerate")
		- Input.get_action_strength("brake")
	)

	steer_input = (
		Input.get_action_strength("steer_right")
		- Input.get_action_strength("steer_left")
	)

# ==================================================
# SURFACE DETECTION
# ==================================================

func update_surface() -> void:
	if !ground_ray.is_colliding():
		surface_grip_mul = grip_dirt
		return

	var collider: Object = ground_ray.get_collider()
	if collider and collider.is_in_group("surface_dirt"):
		surface_grip_mul = grip_dirt
	else:
		surface_grip_mul = grip_tarmac

# ==================================================
# SUSPENSION
# ==================================================

func apply_suspension() -> void:
	if !ground_ray.is_colliding():
		return

	var ray_origin: Vector3 = ground_ray.global_transform.origin
	var hit_point: Vector3 = ground_ray.get_collision_point()

	var hit_dist: float = ray_origin.distance_to(hit_point)

	var compression: float = clamp(
		(suspension_rest_length - hit_dist) / suspension_rest_length,
		0.0,
		1.0
	)

	var spring_force: float = compression * suspension_stiffness

	var vertical_speed: float = linear_velocity.dot(transform.basis.y)
	var damping_force: float = -vertical_speed * suspension_damping

	var total_force: float = spring_force + damping_force

	apply_central_force(transform.basis.y * total_force)
# ==================================================
# ENGINE / BRAKE (REAR AXLE)
# ==================================================

func apply_engine_force() -> void:
	if !is_grounded():
		return

	var forward: Vector3 = -transform.basis.z
	var force: Vector3 = forward * throttle * engine_force * surface_grip_mul

	apply_force(force, transform.basis.z * rear_axle_offset)

# ==================================================
# LATERAL GRIP — CORE RALLY LOGIC
# ==================================================

func apply_lateral_forces() -> void:
	if !is_grounded():
		return

	var forward: Vector3 = -transform.basis.z
	var right: Vector3 = transform.basis.x

	var speed: float = linear_velocity.length()
	if speed < 1.0:
		return

	var forward_speed: float = linear_velocity.dot(forward)
	var lateral_speed: float = linear_velocity.dot(right)

	# Slip angle (radians)
	var slip_angle: float = atan2(abs(lateral_speed), abs(forward_speed))

	var base_grip: float = surface_grip_mul * mass

	var front_grip: float = base_grip
	var rear_grip: float = base_grip

	# Dirt bias — rear breaks first
	if surface_grip_mul < 0.6:
		rear_grip *= 0.35
		front_grip *= 0.85

	# Handbrake kills rear grip
	if Input.is_action_pressed("handbrake"):
		rear_grip *= 0.2

	# ----------------------------------
	# NONLINEAR GRIP COLLAPSE (CRITICAL)
	# ----------------------------------

	if slip_angle > 0.35:
		var loss: float = clamp((slip_angle - 0.35) / 0.4, 0.0, 1.0)
		front_grip *= lerp(1.0, 0.25, loss)
		rear_grip *= lerp(1.0, 0.6, loss)

	# Steering loses authority while sliding
	var steer_effect: float = steer_input * steer_strength
	steer_effect *= clamp(1.0 - slip_angle * 1.4, 0.2, 1.0)

	var front_lateral: float = lateral_speed - steer_effect * speed

	var front_force: Vector3 = -right * front_lateral * front_grip
	var rear_force: Vector3 = -right * lateral_speed * rear_grip

	front_force = front_force.limit_length(max_lateral_force)
	rear_force = rear_force.limit_length(max_lateral_force * 0.6)

	apply_force(front_force, transform.basis.z * front_axle_offset)
	apply_force(rear_force, transform.basis.z * rear_axle_offset)

# ==================================================
# DOWNFORCE
# ==================================================

func apply_downforce() -> void:
	if !is_grounded():
		return

	var df_mul: float = lerp(0.15, 1.0, surface_grip_mul)

	apply_central_force(
		-transform.basis.y
		* downforce
		* df_mul
		* linear_velocity.length()
	)

# ==================================================
# GROUND CHECK
# ==================================================

func is_grounded() -> bool:
	return ground_ray.is_colliding()
