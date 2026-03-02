extends CanvasLayer

# Reference to the car - assign this in the editor or via code
@export var car: RigidBody3D

# UI Elements - create these as children of this CanvasLayer
@onready var speed_label: Label = $SpeedLabel

func _ready():
	# If car not assigned, try to find it automatically
	if car == null:
		car = get_tree().get_first_node_in_group("player_car")
		if car == null:
			# Fallback: try to get parent if HUD is child of car
			var parent = get_parent()
			if parent is RigidBody3D:
				car = parent

func _process(_delta: float):
	if car == null:
		return
	
	# Calculate speed in km/h (same formula as AWD.gd)
	var speed_kph: float = car.linear_velocity.length() * 3.6
	
	# Update the speed display
	speed_label.text = "%d km/h" % int(speed_kph)
