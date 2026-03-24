# ==============================================================================
# GravelSurface.gd
# Loose gravel: good traction at low speed, tendency to slide, reduced braking.
# Assign this as the gravel_surface on the RallyController node.
# Collider group name: "Gravel"
# ==============================================================================
class_name GravelSurface
extends SurfaceData

func _init() -> void:
	# --- Suspension ---
	spring_stiffness        = 100000.0
	spring_progressive_rate = 2.0
	damping_compression     = 20000.0
	damping_rebound         = 18000.0
	rest_length             = 0.65
	max_compression         = 0.5
	bump_stop_stiffness     = 100000.0
	arb_stiffness_front     = 12000.0
	arb_stiffness_rear      = 18000.0

	# --- Performance ---
	torque_multiplier    = 1.5    # Extra torque compensates for loose surface
	top_speed_multiplier = 1.0    # Same top speed as baseline
	power_multiplier     = 1.0
	brake_multiplier     = 0.45   # 35% less effective — gravel rolls under tyres
	speed_drag           = 250.0  # Surface resistance kills top speed naturally
	speed_boost          = 0.0

	# --- Grip & Sliding ---
	lateral_grip_multiplier   = 1.0    # Baseline lateral grip
	slide_drag                = 800.0  # Low drag — slides feel floaty, momentum preserved
	countersteer_grip_penalty = 0.4    # 60% grip loss when sliding — hard to catch
	slide_threshold_deg       = 3.0    # Slide penalty starts early (3°)

	# --- Pacejka Front ---
	# Moderate peak, broad curve — grippy at small angles, falls away gradually
	front_B = 6.5
	front_C = 2.0
	front_D = 1.7   # Peak grip coefficient
	front_E = 0.2

	# --- Pacejka Rear ---
	# Slightly less grip than front — encourages rear-first slides
	rear_B  = 6.5
	rear_C  = 2.0
	rear_D  = 1.5
	rear_E  = 0.2
