extends Node
class_name CoPilot

# ==============================================================================
# CoPilot.gd
# Reads pace notes when the car drives through Area3D trigger zones.
# Each note in the book maps 1-to-1 with an Area3D in the stage scene.
# See: PaceNote.gd, PaceNoteBook.gd
# ==============================================================================

signal note_called(note: PaceNote)        ## Fires when a note starts being read
signal note_finished(note: PaceNote)      ## Fires when the audio chain ends
signal lookahead_changed(notes: Array)    ## Fires after each call with upcoming notes
signal stage_complete()                   ## Fires after the last note is read

# --- Setup ---
@export_group("Setup")
@export var note_book: PaceNoteBook
@export var car: NodePath
## Parent node that holds all PaceNoteTrigger Area3D nodes.
## In the scene tree it should look like:
##   StageTriggers  <-- assign this
##     PaceNoteTrigger_0
##     PaceNoteTrigger_1
##     PaceNoteTrigger_2  ...
@export var triggers_parent: NodePath

# --- Audio ---
@export_group("Audio")
## AudioStreamPlayer3D placed at the co-pilot seat position.
@export var voice_player: AudioStreamPlayer3D
## Folder containing .ogg clips, one per keyword.
## Required files: left.ogg  right.ogg  straight.ogg
##                 1.ogg  2.ogg  3.ogg  4.ogg  5.ogg  flat.ogg
##                 One .ogg per modifier word you use (tightens.ogg, caution.ogg)
@export var audio_folder: String = "res://audio/copilot/"
## Gap in seconds between two clips in a single note call (e.g. "left" then "3").
@export var clip_gap_seconds: float = 0.08
## Minimum seconds before another note can fire. Prevents overlap on tight sections.
@export var min_call_gap_seconds: float = 1.0

# --- Look-ahead ---
@export_group("Look-ahead")
## How many upcoming notes to include in the lookahead_changed signal.
@export var lookahead_count: int = 3

# --- Internal ---
var _car_node: RigidBody3D
var _notes: Array[PaceNote] = []
var _triggers: Array = []
var _last_call_time: float = -999.0
var _running: bool = false

# ==============================================================================
# READY
# ==============================================================================

func _ready() -> void:
	if car:
		_car_node = get_node(car)
	if note_book:
		_load_notes()

# ==============================================================================
# PUBLIC API
# ==============================================================================

## Call this when the stage countdown ends.
func start() -> void:
	if not note_book:
		push_error("[CoPilot] No note_book assigned.")
		return
	_load_notes()
	_connect_triggers()
	_running = true
	_emit_lookahead(0)
	print("[CoPilot] Started - %d notes, %d triggers." % [_notes.size(), _triggers.size()])

## Pause reading (e.g. during a pause menu).
func stop() -> void:
	_running = false

# ==============================================================================
# INTERNAL - SETUP
# ==============================================================================

func _load_notes() -> void:
	_notes = note_book.notes.duplicate()

func _connect_triggers() -> void:
	if not triggers_parent:
		push_error("[CoPilot] triggers_parent not assigned.")
		return

	var parent = get_node(triggers_parent)
	_triggers.clear()

	for i in range(_notes.size()):
		var expected_name = "PaceNoteTrigger_%d" % i
		var area = parent.get_node_or_null(expected_name)

		if area == null:
			push_warning("[CoPilot] Missing Area3D '%s' under triggers parent." % expected_name)
			_triggers.append(null)
			continue

		if not area is Area3D:
			push_warning("[CoPilot] '%s' is not an Area3D." % expected_name)
			_triggers.append(null)
			continue

		_triggers.append(area)
		area.body_entered.connect(_on_trigger_entered.bind(i))

# ==============================================================================
# INTERNAL - TRIGGERING
# ==============================================================================

func _on_trigger_entered(body: Node3D, note_index: int) -> void:
	if not _running:
		return
	if body != _car_node:
		return
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_call_time < min_call_gap_seconds:
		return
	_last_call_time = now
	_call_note(note_index)

func _call_note(index: int) -> void:
	if index < 0 or index >= _notes.size():
		return

	var note = _notes[index]
	var words = _build_word_list(note)

	print("[CoPilot] %s" % " ".join(words))
	emit_signal("note_called", note)
	_emit_lookahead(index + 1)

	if voice_player:
		_play_word_chain(words, note)
	else:
		emit_signal("note_finished", note)

	if index == _notes.size() - 1:
		emit_signal("stage_complete")

# ==============================================================================
# INTERNAL - SPEECH
# ==============================================================================

func _build_word_list(note: PaceNote) -> Array[String]:
	var words: Array[String] = []

	match note.direction:
		PaceNote.Direction.LEFT:     words.append("left")
		PaceNote.Direction.RIGHT:    words.append("right")
		PaceNote.Direction.STRAIGHT: words.append("straight")

	if note.severity >= 6:
		words.append("flat")
	elif note.severity >= 1:
		words.append(str(note.severity))

	for mod in note.modifiers:
		words.append(mod.to_lower().replace(" ", "_"))

	return words

func _play_word_chain(words: Array[String], note: PaceNote) -> void:
	var delay = 0.0

	for word in words:
		var path   = audio_folder + word + ".ogg"
		var stream = load(path) if ResourceLoader.exists(path) else null

		if stream:
			get_tree().create_timer(delay).timeout.connect(
				func(): voice_player.stream = stream; voice_player.play()
			)
			delay += stream.get_length() + clip_gap_seconds
		else:
			push_warning("[CoPilot] Missing clip: %s" % path)
			delay += 0.45

	get_tree().create_timer(delay).timeout.connect(
		func(): emit_signal("note_finished", note)
	)

func _emit_lookahead(from_index: int) -> void:
	var ahead: Array = []
	for i in range(from_index, min(from_index + lookahead_count, _notes.size())):
		ahead.append(_notes[i])
	emit_signal("lookahead_changed", ahead)
