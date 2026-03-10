extends Resource
class_name PaceNote

# ==============================================================================
# PaceNote.gd
# A single pace note — a labelled segment inside the co-pilot's WAV file.
# Enter times as minutes + seconds exactly as you read them in Audacity.
# Example: 1:52.3 in Audacity = start_minutes:1  start_seconds:52.3
# ==============================================================================

@export var label: String = ""

@export_group("Start Time")
@export var start_minutes: int = 0
@export var start_seconds: float = 0.0

@export_group("End Time")
@export var end_minutes: int = 0
@export var end_seconds: float = 0.0

## Returns the start time as a raw float in seconds — used internally by CoPilot.
func get_start() -> float:
	return start_minutes * 60.0 + start_seconds

## Returns the end time as a raw float in seconds — used internally by CoPilot.
func get_end() -> float:
	return end_minutes * 60.0 + end_seconds

## Returns the duration in seconds.
func get_duration() -> float:
	return get_end() - get_start()
