extends Resource
class_name PaceNoteBook

# ==============================================================================
# PaceNoteBook.gd
# A complete set of pace notes for one stage.
# Save as a .tres file per stage: e.g. "res://stages/monte_carlo_ss1_notes.tres"
# ==============================================================================

@export var stage_name: String  = "Unnamed Stage"
@export var stage_id: String    = ""           ## Optional short ID ("SS1", "MC_SS3")
@export var author: String      = ""           ## Who wrote the notes
@export var version: int        = 1            ## Increment when notes are revised

## The ordered list of pace notes for this stage.
@export var notes: Array[PaceNote] = []

# ==============================================================================
# BUILDER HELPERS — create note books in code cleanly
# ==============================================================================

## Append a note and return self for chaining.
## Example:
##   book.add("left", 3).add("right", 1, ["don't cut"]).add("right", 4, ["over crest"])
func add(direction: String, severity: int,
		modifiers: Array[String] = [], distance_m: float = 0.0,
		note_text: String = "") -> PaceNoteBook:

	var note            := PaceNote.new()
	note.severity        = clamp(severity, 1, 6)
	note.modifiers       = modifiers
	note.distance_m      = distance_m
	note.note_text       = note_text

	match direction.to_lower():
		"left":     note.direction = PaceNote.Direction.LEFT
		"right":    note.direction = PaceNote.Direction.RIGHT
		_:          note.direction = PaceNote.Direction.STRAIGHT

	notes.append(note)
	return self

## Recalculates [distance_to_next_m] for every note based on their [distance_m].
## Call this after building or editing a book.
func recalculate_distances() -> void:
	for i in range(notes.size() - 1):
		notes[i].distance_to_next_m = notes[i + 1].distance_m - notes[i].distance_m
	if notes.size() > 0:
		notes[-1].distance_to_next_m = 0.0

## Returns a plain-text recce sheet — useful for debugging or printing.
func to_recce_sheet() -> String:
	var lines: Array[String] = []
	lines.append("=== %s (v%d) — %d notes ===" % [stage_name, version, notes.size()])
	for i in range(notes.size()):
		var n   = notes[i]
		var dst = ("%.0fm" % n.distance_m) if n.distance_m > 0 else "---"
		lines.append("  [%03d] %5s  %s" % [i, dst, n.to_label()])
	return "\n".join(lines)

## Quick factory — returns a pre-filled demo book for testing.
static func make_demo() -> PaceNoteBook:
	var book        := PaceNoteBook.new()
	book.stage_name  = "Demo Stage"
	book.stage_id    = "DEMO"

	book.add("right", 4,  [],                    0.0,   "Start hairpin")
	book.add("left",  3,  ["tightens"],           120.0, "Tightening bend")
	book.add("right", 2,  ["don't cut"],          240.0, "Narrow section")
	book.add("left",  5,  ["over crest"],         370.0, "Blind crest")
	book.add("right", 1,  ["caution"],            480.0, "Hairpin — gravel on exit")
	book.add("left",  4,  [],                     590.0)
	book.add("right", 3,  ["into junction"],      690.0)
	book.add("left",  6,  [],                     780.0, "Flat through trees")
	book.add("right", 2,  ["tightens","caution"], 900.0)
	book.add("straight",0,[],                     980.0, "Jump")
	book.add("left",  3,  [],                     1020.0)
	book.add("right", 5,  ["opens"],              1110.0)
	book.add("left",  1,  ["don't cut"],          1200.0, "Finish hairpin")

	book.recalculate_distances()
	return book
