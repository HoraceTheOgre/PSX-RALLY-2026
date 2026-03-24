extends Node3D
# Plays a constant looping crowd sound at this node's position.


@export var sound: AudioStream
@export var volume_db: float = 0.0
@export var max_distance: float = 30.0

@onready var _player: AudioStreamPlayer3D = $AudioStreamPlayer3D

func _ready() -> void:
	_player.stream      = sound
	_player.volume_db   = volume_db
	_player.max_distance = max_distance
	_player.play()
