# ==============================================================================
# TarmacSurface.gd
# Smooth tarmac: high grip, responsive braking, higher top speed, stiffer ride.
# Assign this as the tarmac_surface on the RallyController node.
# Collider group name: "Tarmac"  (or any collider NOT in "Gravel" / "Grass")
# ==============================================================================
class_name TarmacSurface
extends SurfaceData

func _init() -> void:
	# --- Suspension ---
	# Stiffer springs and damping for the firmer road surface
	spring_stiffness        = 110000.0
	spring_progressive_rate = 1.5
	damping_compression     = 22000.0
	damping_rebound         = 20000.0
	rest_length             = 0.65
	max_compression         = 0.5
	bump_stop_stiffness     = 140000.0
	arb_stiffness_front     = 18000.0   # Much stiffer ARBs — less body roll on tarmac
	arb_stiffness_rear      = 20000.0

	# --- Performance ---
	torque_multiplier    = 1.0    # No torque boost needed on grippy surface
	top_speed_multiplier = 1.4    # 40% higher top speed on smooth tarmac
	power_multiplier     = 1.5    # 50% more usable power
	brake_multiplier     = 1.0    # Full braking effectiveness
	speed_drag           = 0.0    # No extra surface drag
	speed_boost          = 150.0  # Slight aerodynamic speed advantage at high speed

	# --- Grip & Sliding ---
	lateral_grip_multiplier   = 1.5    # 50% more lateral grip than gravel
	slide_drag                = 3500.0 # High — tarmac scrubs speed fast when sliding
	countersteer_grip_penalty = 1.0    # No penalty — front grip is always there
	slide_threshold_deg       = 999.0  # Effectively disabled — tarmac doesn't slide easily

	# --- Pacejka Front ---
	# Sharp peak, narrow curve — high grip but falls away quickly if pushed past limit
	front_B = 11.0
	front_C = 1.3
	front_D = 1.2   # Peak grip coefficient (lower than gravel D but × lateral_grip_multiplier = 1.8 effective)
	front_E = -0.1  # Negative E = more progressive falloff past peak

	# --- Pacejka Rear ---
	rear_B  = 10.0
	rear_C  = 1.4
	rear_D  = 1.1
	rear_E  = -0.1
