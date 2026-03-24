# ==============================================================================
# SurfaceData.gd
# Base Resource class that defines all parameters for a driving surface.
# Create a subclass (GravelSurface, TarmacSurface, GrassSurface) or assign
# this directly in the Inspector with custom values.
# ==============================================================================
class_name SurfaceData
extends Resource

# --- Suspension ---
@export_group("Suspension")
@export var spring_stiffness: float        = 100000.0
@export var spring_progressive_rate: float = 2.0
@export var damping_compression: float     = 20000.0
@export var damping_rebound: float         = 18000.0
@export var rest_length: float             = 0.65
@export var max_compression: float         = 0.5
@export var bump_stop_stiffness: float     = 100000.0
@export var arb_stiffness_front: float     = 12000.0
@export var arb_stiffness_rear: float      = 18000.0

# --- Performance ---
@export_group("Performance")
@export var torque_multiplier: float    = 1.0   # Engine torque scaling
@export var top_speed_multiplier: float = 1.0   # Scales max speed
@export var power_multiplier: float     = 1.0   # Scales engine power output
@export var brake_multiplier: float     = 1.0   # 1.0 = full brakes, <1 = reduced
@export var speed_drag: float           = 0.0   # Extra drag force at speed
@export var speed_boost: float          = 0.0   # Extra forward force at speed

# --- Grip & Sliding ---
@export_group("Grip & Sliding")
@export var lateral_grip_multiplier: float      = 1.0   # Lateral grip scaling
@export var slide_drag: float                   = 800.0 # Drag when sliding sideways
@export var countersteer_grip_penalty: float    = 1.0   # Front grip penalty when sliding (1=none, 0=no grip)
@export var slide_threshold_deg: float          = 3.0   # Degrees of slip before penalty kicks in

# --- Pacejka Tire Model ---
# Magic Formula: D * sin(C * atan(B*x - E*(B*x - atan(B*x))))
# B = Stiffness factor (higher = sharper peak)
# C = Shape factor     (higher = wider curve)
# D = Peak value       (scales max lateral force — MAIN GRIP KNOB)
# E = Curvature factor (negative = more progressive falloff)

@export_group("Pacejka - Front Axle")
@export var front_B: float = 6.5
@export var front_C: float = 2.0
@export var front_D: float = 1.7  ## Peak lateral force coefficient
@export var front_E: float = 0.2

@export_group("Pacejka - Rear Axle")
@export var rear_B: float  = 6.5
@export var rear_C: float  = 2.0
@export var rear_D: float  = 1.5  ## Peak lateral force coefficient
@export var rear_E: float  = 0.2

# --- Helpers ---

## Returns Pacejka params dict for the given axle.
func get_pacejka(is_rear: bool) -> Dictionary:
	if is_rear:
		return { "B": rear_B,  "C": rear_C,  "D": rear_D,  "E": rear_E  }
	return     { "B": front_B, "C": front_C, "D": front_D, "E": front_E }

## Returns a new SurfaceData lerped between self and [other] by [t] (0=self, 1=other).
## Used when transitioning between surfaces mid-blend.
func lerp_with(other: SurfaceData, t: float) -> SurfaceData:
	var out                       := SurfaceData.new()
	out.spring_stiffness          = lerp(spring_stiffness,          other.spring_stiffness,          t)
	out.spring_progressive_rate   = lerp(spring_progressive_rate,   other.spring_progressive_rate,   t)
	out.damping_compression       = lerp(damping_compression,       other.damping_compression,       t)
	out.damping_rebound           = lerp(damping_rebound,           other.damping_rebound,           t)
	out.rest_length               = lerp(rest_length,               other.rest_length,               t)
	out.max_compression           = lerp(max_compression,           other.max_compression,           t)
	out.bump_stop_stiffness       = lerp(bump_stop_stiffness,       other.bump_stop_stiffness,       t)
	out.arb_stiffness_front       = lerp(arb_stiffness_front,       other.arb_stiffness_front,       t)
	out.arb_stiffness_rear        = lerp(arb_stiffness_rear,        other.arb_stiffness_rear,        t)
	out.torque_multiplier         = lerp(torque_multiplier,         other.torque_multiplier,         t)
	out.top_speed_multiplier      = lerp(top_speed_multiplier,      other.top_speed_multiplier,      t)
	out.power_multiplier          = lerp(power_multiplier,          other.power_multiplier,          t)
	out.brake_multiplier          = lerp(brake_multiplier,          other.brake_multiplier,          t)
	out.speed_drag                = lerp(speed_drag,                other.speed_drag,                t)
	out.speed_boost               = lerp(speed_boost,               other.speed_boost,               t)
	out.lateral_grip_multiplier   = lerp(lateral_grip_multiplier,   other.lateral_grip_multiplier,   t)
	out.slide_drag                = lerp(slide_drag,                other.slide_drag,                t)
	out.countersteer_grip_penalty = lerp(countersteer_grip_penalty, other.countersteer_grip_penalty, t)
	out.slide_threshold_deg       = lerp(slide_threshold_deg,       other.slide_threshold_deg,       t)
	out.front_B = lerp(front_B, other.front_B, t)
	out.front_C = lerp(front_C, other.front_C, t)
	out.front_D = lerp(front_D, other.front_D, t)
	out.front_E = lerp(front_E, other.front_E, t)
	out.rear_B  = lerp(rear_B,  other.rear_B,  t)
	out.rear_C  = lerp(rear_C,  other.rear_C,  t)
	out.rear_D  = lerp(rear_D,  other.rear_D,  t)
	out.rear_E  = lerp(rear_E,  other.rear_E,  t)
	return out
