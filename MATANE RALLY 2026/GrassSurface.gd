# ==============================================================================
# GrassSurface.gd
# Wet/dewy grass: very low grip, heavy sliding, poor braking, soft surface.
# The car will understeer into corners and the rear will step out easily.
# Catching slides requires careful throttle control.
# Assign this as the grass_surface on the RallyController node.
# Collider group name: "Grass"
# ==============================================================================
class_name GrassSurface
extends SurfaceData

func _init() -> void:
	# --- Suspension ---
	# Softer than gravel — grass is typically over soft soil, more travel needed
	spring_stiffness        = 82000.0
	spring_progressive_rate = 2.5    # More progressive — bottoms out on bumps
	damping_compression     = 15000.0
	damping_rebound         = 13000.0
	rest_length             = 0.70   # Slightly higher ride height
	max_compression         = 0.55   # More suspension travel available
	bump_stop_stiffness     = 75000.0
	arb_stiffness_front     = 7000.0  # Soft ARBs — lots of body roll in corners
	arb_stiffness_rear      = 9000.0

	# --- Performance ---
	torque_multiplier    = 1.3    # Need more torque to move on soft surface
	top_speed_multiplier = 0.85   # 15% lower top speed — grass slows you down
	power_multiplier     = 0.9    # Slight power loss (wheelspin reduces traction)
	brake_multiplier     = 0.45   # Brakes are nearly useless — grass offers no resistance
	speed_drag           = 420.0  # Heavy surface drag — grass acts like a brake at speed
	speed_boost          = 0.0

	# --- Grip & Sliding ---
	# KEY VALUES — these make grass feel distinctly dangerous:
	lateral_grip_multiplier   = 0.65   # Only 65% of gravel's lateral grip
	slide_drag                = 500.0  # Very low drag — slides are long and floaty
	countersteer_grip_penalty = 0.25   # 75% grip loss when sliding — almost impossible to catch
	slide_threshold_deg       = 2.0    # Penalty starts at just 2° — slides begin very early

	# --- Pacejka Front ---
	# Low peak, wide curve — builds slowly, never feels really grippy, falls off gently
	# D=0.65 is the main knob: ~38% of tarmac's effective grip
	front_B = 5.0   # Low stiffness — grip builds gradually with slip angle
	front_C = 1.9   # Wide shape — rounded peak, no sudden snap
	front_D = 0.65  # LOW PEAK GRIP — the defining characteristic of grass
	front_E = 0.35  # Positive E — very rounded curve, no sharp falloff

	# --- Pacejka Rear ---
	# Even less rear grip than front — guarantees oversteer tendency
	rear_B  = 4.5
	rear_C  = 1.9
	rear_D  = 0.52  # Rear grip is noticeably less than front
	rear_E  = 0.35
