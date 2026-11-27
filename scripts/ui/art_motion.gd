extends Node2D

@onready var pulse: AnimatedSprite2D = $Pulse
@onready var sparks: CPUParticles2D = $Sparks

func _ready() -> void:
	pulse.play()
	sparks.emitting = true
	get_tree().create_timer(1.2).timeout.connect(queue_free)
