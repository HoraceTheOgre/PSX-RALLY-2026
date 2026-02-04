extends VehicleBody3D

# ==========================================
#           RALLY CONTROLLER V7 (KM/H)
# ==========================================

# --- 1. ENGINE & MOMENTUM ---
@export_group("Power Settings")
@export var MAX_SPEED_KMH = 210.0    # Converted (was 130 mph)
@export var ACCELERATION = 5000.0    # Engine Torque
@export var GRAVEL_POWER_LOSS = 1.0  # Keep 1.0 (Physics handles drag, we handle drift)
@export var DRIFT_PUSH = 3500.0      # The "Ridge Racer" forward push force

@export_group("Braking")
@export var BRAKE_POWER = 60.0       # Brake Strength
@export var REVERSE_POWER = 2000.0

# --- 2. STEERING ---
@export_group("Steering")
@export var STEER_ANGLE = 0.5        # Max wheel angle (Radians)
@export var STEER_SPEED = 4.0        # Reaction speed

# --- 3. HANDLING & GRIP ---
@export_group("Tarmac Handling")
@export var grip_tarmac_front = 6.0 
@export var grip_tarmac_rear = 5.5   

@export_group("Gravel Handling")
@export var grip_dirt_front = 5.0    # High grip to steer
@export var grip_dirt_rear = 1.5     # Low grip to slide
@export var drift_slip = 1.2         # Handbrake grip

# --- INTERNAL VARIABLES ---
var current_surface = "Tarmac"
var wheels = []
var front_wheels = []
var rear_wheels = []

func _ready():
	# Center of Mass: Low and slightly forward
	center_of_mass = Vector3(0, -1.0, 0.2)
	
	wheels.clear()
	front_wheels.clear()
	rear_wheels.clear()
	
	for child in get_children():
		if child is VehicleWheel3D:
			wheels.append(child)
			if child.name == "FR" or child.name == "FL":
				front_wheels.append(child)
			elif child.name == "BR" or child.name == "BL":
				rear_wheels.append(child)
	
	print("Rally V7 Ready (KM/H Mode).")

func _physics_process(delta):
	# CONVERSION: Meters/Sec * 3.6 = KM/H
	var speed_kmh = linear_velocity.length() * 3.6
	
	# DEBUG: Print speed 4 times a second
	if Engine.get_physics_frames() % 15 == 0:
		print("SPEED: %.1f km/h" % speed_kmh)
	
	process_surface_logic()
	apply_rally_grip()
	process_controls(delta, speed_kmh)
	
	# STABILIZERS
	apply_central_force(Vector3.DOWN * 4000.0) 
	if is_on_ground():
		rotation.z = lerp(rotation.z, 0.0, 5.0 * delta)

func process_controls(delta, speed_kmh):
	var gas = Input.get_action_strength("accelerate")
	var brake_val = Input.get_action_strength("brake")
	var turn = Input.get_axis("steer_left", "steer_right")
	
	engine_force = 0
	brake = 0
	
	# --- 1. ACCELERATION ---
	if gas > 0:
		if speed_kmh < MAX_SPEED_KMH:
			# A. Wheel Power
			var torque = -ACCELERATION * gas
			if current_surface == "Dirt":
				torque *= GRAVEL_POWER_LOSS
			engine_force = torque
			
			# B. DRIFT PUSH (Ridge Racer Logic)
			# Only push if moving faster than 25 KM/H
			if current_surface == "Dirt" and speed_kmh > 25.0:
				var cam = get_viewport().get_camera_3d()
				if cam:
					var cam_dir = -cam.global_transform.basis.z
					cam_dir.y = 0 
					cam_dir = cam_dir.normalized()
					apply_central_force(cam_dir * DRIFT_PUSH * gas)
					
	# --- 2. ROTATIONAL ASSIST ---
	# Helps twist the car into the turn
	if current_surface == "Dirt" and abs(turn) > 0.1 and gas > 0:
		var turn_force = 6000.0 * turn
		
		# If going slow (< 30 KM/H), reduce twist so you don't spin out
		if speed_kmh < 30.0:
			turn_force *= 0.5
			
		apply_torque(Vector3.UP * -turn_force)

	# --- 3. BRAKING ---
	if brake_val > 0:
		if linear_velocity.dot(-transform.basis.z) > 2.0:
			brake = BRAKE_POWER * brake_val
		else:
			engine_force = REVERSE_POWER * brake_val

	# --- 4. STEERING ---
	# Speed Sensitivity: 320 KM/H is roughly 200 MPH.
	# We reduce steering as we get closer to 320 KM/H.
	var speed_factor = clamp(1.0 - (speed_kmh / 320.0), 0.7, 1.0)
	var target_angle = turn * -STEER_ANGLE * speed_factor
	steering = move_toward(steering, target_angle, STEER_SPEED * delta)

func process_surface_logic():
	var dirt_count = 0
	for w in wheels:
		var collider = w.get_contact_body()
		if collider:
			if collider.is_in_group("surface_dirt") or "Dirt" in collider.name:
				dirt_count += 1
			elif collider.get_parent().is_in_group("surface_dirt") or "Dirt" in collider.get_parent().name:
				dirt_count += 1
	
	if dirt_count >= 1:
		if current_surface != "Dirt":
			# print(">>> GRAVEL MODE")
			current_surface = "Dirt"
	else:
		if current_surface != "Tarmac":
			# print(">>> TARMAC MODE")
			current_surface = "Tarmac"

func apply_rally_grip():
	var f_val = grip_tarmac_front
	var r_val = grip_tarmac_rear
	
	if current_surface == "Dirt":
		f_val = grip_dirt_front
		r_val = grip_dirt_rear
		
	if Input.is_action_pressed("handbrake"):
		r_val = drift_slip
		
	for w in front_wheels:
		w.wheel_friction_slip = f_val
	for w in rear_wheels:
		w.wheel_friction_slip = r_val

func is_on_ground() -> bool:
	for w in wheels:
		if w.is_in_contact(): return true
	return false
