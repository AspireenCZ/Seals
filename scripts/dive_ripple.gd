extends Node2D
## Lingering water ripple at a dive spot — bright pulsing rings that fade over 5 seconds.

var _time := 0.0
const LIFETIME := 5.0

func _process(delta: float) -> void:
	_time += delta
	if _time >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var frac := _time / LIFETIME
	var alpha := (1.0 - frac) * 0.8
	var pulse := sin(_time * 3.0) * 0.12 + 1.0
	# Outer ring — expanding, bright
	var r1 := 30.0 + _time * 8.0
	draw_arc(Vector2.ZERO, r1 * pulse, 0, TAU, 32, Color(0.4, 0.7, 1.0, alpha * 0.5), 2.5)
	# Second ring
	var r2 := 20.0 + _time * 5.5
	draw_arc(Vector2.ZERO, r2 * pulse, 0, TAU, 28, Color(0.5, 0.78, 1.0, alpha * 0.7), 3.0)
	# Middle ring — bright core
	var r3 := 12.0 + _time * 3.0
	draw_arc(Vector2.ZERO, r3 * pulse, 0, TAU, 24, Color(0.65, 0.85, 1.0, alpha * 0.85), 2.5)
	# Inner ripple — small, brightest
	var r4 := 5.0 + sin(_time * 5.0) * 3.0
	draw_arc(Vector2.ZERO, maxf(r4, 2.0), 0, TAU, 20, Color(0.8, 0.92, 1.0, alpha), 2.0)
	# Water disturbance fill — faint disc
	if frac < 0.5:
		var fill_alpha := alpha * 0.15
		draw_circle(Vector2.ZERO, r3 * 0.7, Color(0.3, 0.55, 0.9, fill_alpha))
	# Bubble dots — more and brighter
	if frac < 0.75:
		var bubble_alpha := alpha * 0.9
		for i in range(5):
			var angle := _time * (1.3 + i * 0.6) + i * TAU / 5.0
			var dist := 10.0 + sin(_time * 2.0 + i) * 7.0
			var bp := Vector2(cos(angle) * dist, sin(angle) * dist)
			draw_circle(bp, 2.0 + sin(_time * 4.0 + i * 2.0) * 0.8, Color(0.85, 0.95, 1.0, bubble_alpha))
