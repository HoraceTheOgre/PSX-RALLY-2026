extends Node
class_name CoPilot

# ==============================================================================
# CoPilot.gd
# Plays pace notes from a continuous WAV file when the car passes Area3D triggers.
# ==============================================================================

signal note_called(note: PaceNote)
signal note_finished(note: PaceNote)
signal stage_complete()

@export_group("Setup")
@export var note_book: PaceNoteBook
@export var car: NodePath
@export var triggers_parent: NodePath

@export_group("Audio")
@export var voice_player: AudioStreamPlayer
@export var min_call_gap_seconds: float = 0.5

var _car_node: RigidBody3D
var _notes: Array[PaceNote] = []
var _last_call_time: float = -999.0
var _running: bool = false
var _stop_timer: Timer
var _current_note: PaceNote = null

# ==============================================================================
# READY
# ==============================================================================

func _ready() -> void:
	if car:
		_car_node = get_node(car)

	_stop_timer = Timer.new()
	_stop_timer.one_shot = true
	_stop_timer.timeout.connect(_on_clip_ended)
	add_child(_stop_timer)

# ==============================================================================
# PUBLIC API
# ==============================================================================

func start() -> void:
	if not note_book:
		push_error("[CoPilot] No note_book assigned.")
		return
	if not voice_player:
		push_error("[CoPilot] No voice_player assigned.")
		return
	if not note_book.audio_file:
		push_error("[CoPilot] No audio_file set in the PaceNoteBook resource.")
		return

	_notes = note_book.notes.duplicate()

	# Assign the stream once and leave it — we seek into it each time
	voice_player.stream = note_book.audio_file
	# Autoplay must be OFF on the AudioStreamPlayer node, we call play() manually
	voice_player.autoplay = false

	_connect_triggers()
	_running = true
	print("[CoPilot] Ready — %d notes loaded." % _notes.size())

func stop() -> void:
	_running = false
	_stop_timer.stop()
	voice_player.stop()

# ==============================================================================
# TRIGGERS
# ==============================================================================

func _connect_triggers() -> void:
	var parent = get_node(triggers_parent)
	if not parent:
		push_error("[CoPilot] triggers_parent not found.")
		return

	for i in range(_notes.size()):
		var area: Area3D = parent.get_node_or_null("PaceNoteTrigger_%d" % i)
		if area == null:
			push_warning("[CoPilot] PaceNoteTrigger_%d not found." % i)
			continue
		area.body_entered.connect(_on_trigger_entered.bind(i))

func _on_trigger_entered(body: Node3D, note_index: int) -> void:
	if not _running or body != _car_node:
		return
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_call_time < min_call_gap_seconds:
		return
	_last_call_time = now
	_play_note(note_index)

# ==============================================================================
# PLAYBACK
# ==============================================================================

func _play_note(index: int) -> void:
	var note: PaceNote = _notes[index]
	var duration = note.get_duration()

	if duration <= 0.0:
		push_warning("[CoPilot] Note %d '%s' has zero or negative duration — check your start/end times." % [index, note.label])
		return

	_stop_timer.stop()
	voice_player.stop()
	_current_note = note

	voice_player.play()
	voice_player.seek(note.get_start())

	_stop_timer.wait_time = duration
	_stop_timer.start()

	print("[CoPilot] Playing '%s'  %dm%ds → %dm%ds  (%.2fs)" % [
		note.label,
		note.start_minutes, note.start_seconds,
		note.end_minutes,   note.end_seconds,
		duration
	])

	emit_signal("note_called", note)

	if index == _notes.size() - 1:
		emit_signal("stage_complete")

func _on_clip_ended() -> void:
	voice_player.stop()
	if _current_note:
		emit_signal("note_finished", _current_note)
	_current_note = null
