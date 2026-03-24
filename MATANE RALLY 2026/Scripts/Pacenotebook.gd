extends Resource
class_name PaceNoteBook

# ==============================================================================
# PaceNoteBook.gd
# Holds the co-pilot WAV file and the list of pace notes for one stage.
# Save one .tres per stage: e.g. res://stages/ss1_notes.tres
# ==============================================================================

@export var stage_name: String = ""

## The single continuous WAV file containing all co-pilot calls for this stage.
@export var audio_file: AudioStream

## Ordered list of pace notes. Index 0 fires at the first trigger, index 1 at
## the second trigger, and so on. The order here must match the order of your
## PaceNoteTrigger_N nodes in the scene.
@export var notes: Array[PaceNote] = []
