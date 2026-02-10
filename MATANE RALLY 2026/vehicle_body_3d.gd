extends VehicleBody3D

const MAX_STEER = 0.8
const ENGINE_POWER = 300 # Increased for testing

func _physics_process(delta: float) -> void:
	# Force brakes to zero to ensure they aren't the problem
	brake = 0.0
	
	var steer_input = Input.get_axis("ui_right", "ui_left")
	var throttle_input = Input.get_axis("ui_down", "ui_up")
	
	steering = move_toward(steering, steer_input * MAX_STEER, delta * 2.5)
	engine_force = throttle_input * ENGINE_POWER
	
	if Engine.get_frames_drawn() % 30 == 0:
		print("--- Movement Debug ---")
		print("Velocity: ", linear_velocity)
		print("Engine Force: ", engine_force)
		# If this is 0, the car is physically stuck on something
		print("Brake Value: ", brake)
