extends Node2D
## Animated arctic ocean — layered waves, caustics, foam, depth gradient.

var _time := 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	# --- Deep wave bands (slow, wide, translucent) ---
	for i in range(6):
		var y := 60.0 + i * 180.0
		var pts: PackedVector2Array = []
		var pts2: PackedVector2Array = []
		for x_step in range(-100, 2100, 12):
			var xf := float(x_step)
			var wave1 := sin(xf * 0.004 + _time * 0.25 + i * 2.1) * 18.0
			var wave2 := sin(xf * 0.007 + _time * 0.4 + i * 1.5) * 8.0
			pts.append(Vector2(xf, y + wave1 + wave2))
			pts2.append(Vector2(xf, y + wave1 + wave2 + 30))
		if pts.size() > 1:
			# Dark trough band
			var band_color := Color(0.08, 0.22, 0.48, 0.2 + i * 0.02)
			for j in range(pts.size() - 1):
				var quad: PackedVector2Array = [pts[j], pts[j + 1], pts2[j + 1], pts2[j]]
				draw_colored_polygon(quad, band_color)

	# --- Medium wave lines (multiple layers) ---
	for layer in range(3):
		var base_alpha := 0.15 + layer * 0.08
		var speed := 0.35 + layer * 0.15
		var amplitude := 5.0 + layer * 3.0
		var freq := 0.006 + layer * 0.002
		var y_offset := layer * 40.0

		for i in range(10):
			var y := 40.0 + i * 110.0 + y_offset
			var pts: PackedVector2Array = []
			for x_step in range(-100, 2100, 16):
				var xf := float(x_step)
				var yy := y + sin(xf * freq + _time * speed + i * 1.7 + layer * 0.9) * amplitude
				yy += cos(xf * freq * 1.6 + _time * speed * 0.7 + i * 2.3) * amplitude * 0.4
				pts.append(Vector2(xf, yy))
			if pts.size() > 1:
				var color := Color(0.25 + layer * 0.08, 0.50 + layer * 0.05, 0.82 - layer * 0.05, base_alpha)
				draw_polyline(pts, color, 1.5 - layer * 0.3)

	# --- Surface caustics (bright spots that drift) ---
	for i in range(20):
		var seed_x := fmod(i * 347.3 + _time * 12.0, 2100.0) - 100.0
		var seed_y := fmod(i * 213.7 + _time * 8.0 + sin(_time * 0.3 + i) * 40, 1200.0) - 60.0
		var brightness := (sin(_time * 1.2 + i * 2.7) + 1.0) * 0.5
		var sz := 3.0 + brightness * 5.0
		var alpha := brightness * 0.12
		draw_circle(Vector2(seed_x, seed_y), sz, Color(0.5, 0.75, 1.0, alpha))

	# --- Foam specks (small white dots that drift slowly) ---
	for i in range(30):
		var fx := fmod(i * 193.1 + _time * 6.0, 2200.0) - 100.0
		var fy := fmod(i * 271.9 + _time * 3.5 + cos(_time * 0.2 + i * 1.1) * 20, 1300.0) - 100.0
		var flicker := (sin(_time * 2.0 + i * 3.3) + 1.0) * 0.5
		var alpha := flicker * 0.18
		var sz := 1.5 + flicker * 2.5
		draw_circle(Vector2(fx, fy), sz, Color(0.85, 0.92, 1.0, alpha))
