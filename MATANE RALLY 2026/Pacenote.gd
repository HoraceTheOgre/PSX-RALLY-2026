extends Resource
class_name PaceNote

# ==============================================================================
# PaceNote.gd
# A single pace note entry. Lives inside a PaceNoteBook array.
# Fill these in the Godot Inspector or build them in code.
# ==============================================================================

enum Direction { LEFT, RIGHT, STRAIGHT }

# --- Core ---
@export var direction: Direction = Direction.LEFT
## 1 = hairpin, 2, 3, 4, 5, 6 = flat. Maps to Copilot.Severity.
@export var severity: int = 3

# --- Modifiers ---
## Free-form modifier words spoken after direction+severity.
## Standard WRC examples: "tightens", "opens", "don't cut", "over crest",
## "into junction", "caution", "maybe", "keep in", "finish"
@export var modifiers: Array[String] = []

# --- Positioning ---
## Odometer distance (metres from stage start) at which this note is triggered.
## Used in DISTANCE trigger mode. Set to 0 if using AREA mode instead.
@export var distance_m: float = 0.0
## Metres to the next note — used to decide if "and" bridging is called.
## Set automatically by PaceNoteBook.recalculate_distances().
@export var distance_to_next_m: float = 0.0

# --- Optional Metadata ---
## Free text description for the editor / recce sheet ("Long left over ridge").
@export_multiline var note_text: String = ""
## Icon key for the HUD arrow strip (e.g. "left_3", "right_hairpin").
## Leave blank to auto-generate from direction + severity.
@export var icon_key: String = ""

# --- Helpers ---

## Returns a short human-readable string, e.g. "Left 3 tightens"
func to_label() -> String:
	var dir_str := ""
	match direction:
		Direction.LEFT:     dir_str = "Left"
		Direction.RIGHT:    dir_str = "Right"
		Direction.STRAIGHT: dir_str = "Straight"

	var sev_str := "Flat" if severity >= 6 else str(severity)
	var mod_str := " ".join(modifiers) if modifiers.size() > 0 else ""
	return ("%s %s %s" % [dir_str, sev_str, mod_str]).strip_edges()

## Returns the auto-generated icon key if [icon_key] is blank.
func get_icon_key() -> String:
	if icon_key != "":
		return icon_key
	var dir_str := ""
	match direction:
		Direction.LEFT:     dir_str = "left"
		Direction.RIGHT:    dir_str = "right"
		Direction.STRAIGHT: dir_str = "straight"
	return "%s_%d" % [dir_str, severity]
