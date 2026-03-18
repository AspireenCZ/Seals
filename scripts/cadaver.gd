extends Node2D
## Cadaver remains — bones and meat left where a kid was eaten.
## Fades out slowly, then frees itself.

var _time := 0.0
const FADE_START := 10.0
const LIFETIME := 15.0

## Randomized pieces generated once in _ready
var _bones: Array[Dictionary] = []
var _meat: Array[Dictionary] = []

func _ready() -> void:
	z_index = -1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Long bones (femur/humerus style) — thick with bulbous ends
	for _i in range(rng.randi_range(3, 5)):
		var pos := Vector2(rng.randf_range(-60, 60), rng.randf_range(-45, 45))
		var angle := rng.randf() * TAU
		var length := rng.randf_range(25, 50)
		var w := rng.randf_range(4.0, 7.0)
		_bones.append({
			type = "long",
			a = pos,
			b = pos + Vector2(cos(angle), sin(angle)) * length,
			width = w,
			cap = w * rng.randf_range(1.2, 1.8),  # bulbous ends
		})
	# Ribs — curved arcs
	var rib_center := Vector2(rng.randf_range(-20, 20), rng.randf_range(-15, 15))
	var rib_angle := rng.randf() * TAU
	for _i in range(rng.randi_range(3, 5)):
		var offset := Vector2(cos(rib_angle + PI * 0.5), sin(rib_angle + PI * 0.5)) * rng.randf_range(-25, 25)
		var pts: PackedVector2Array = []
		var arc_len := rng.randf_range(20, 35)
		var curve := rng.randf_range(0.3, 0.6)
		for s in range(5):
			var t := float(s) / 4.0
			var along := Vector2(cos(rib_angle), sin(rib_angle)) * (t - 0.5) * arc_len
			var perp := Vector2(cos(rib_angle + PI * 0.5), sin(rib_angle + PI * 0.5)) * sin(t * PI) * arc_len * curve
			pts.append(rib_center + offset + along + perp)
		_bones.append({
			type = "rib",
			pts = pts,
			width = rng.randf_range(2.5, 4.0),
		})
	# Small bone fragments
	for _i in range(rng.randi_range(4, 8)):
		var pos := Vector2(rng.randf_range(-55, 55), rng.randf_range(-40, 40))
		var angle := rng.randf() * TAU
		var length := rng.randf_range(8, 18)
		_bones.append({
			type = "frag",
			a = pos,
			b = pos + Vector2(cos(angle), sin(angle)) * length,
			width = rng.randf_range(2.0, 3.5),
		})
	# Joint dots / vertebrae
	for _i in range(rng.randi_range(4, 7)):
		_bones.append({
			type = "dot",
			a = Vector2(rng.randf_range(-50, 50), rng.randf_range(-40, 40)),
			width = rng.randf_range(3.5, 6.0),
		})
	# Skull-ish shape — circle with two eye holes
	var skull_pos := Vector2(rng.randf_range(-35, 35), rng.randf_range(-25, 25))
	_bones.append({
		type = "skull",
		pos = skull_pos,
		radius = rng.randf_range(10, 14),
		angle = rng.randf() * TAU,
	})
	# Meat chunks — larger irregular polygons
	for _i in range(rng.randi_range(5, 8)):
		var center := Vector2(rng.randf_range(-50, 50), rng.randf_range(-40, 40))
		var sz := rng.randf_range(10, 22)
		var pts: PackedVector2Array = []
		var num := rng.randi_range(5, 8)
		for pi in range(num):
			var a := TAU * pi / num
			var r := sz * rng.randf_range(0.4, 1.2)
			pts.append(center + Vector2(cos(a) * r, sin(a) * r))
		_meat.append({
			pts = pts,
			dark = rng.randf() < 0.4,
		})

func _process(delta: float) -> void:
	_time += delta
	if _time >= LIFETIME:
		queue_free()
		return
	if _time > FADE_START:
		modulate.a = 1.0 - (_time - FADE_START) / (LIFETIME - FADE_START)
	queue_redraw()

func _draw() -> void:
	var bone_color := Color(0.92, 0.9, 0.82)
	var bone_shadow := Color(0.78, 0.75, 0.65)
	var meat_color := Color(0.7, 0.15, 0.12)
	var meat_dark := Color(0.5, 0.08, 0.06)
	# Meat first (under bones)
	for m in _meat:
		var c: Color = meat_dark if m["dark"] else meat_color
		draw_colored_polygon(m["pts"], c)
		# Meat outline
		var outline_pts: PackedVector2Array = m["pts"]
		outline_pts.append(outline_pts[0])
		draw_polyline(outline_pts, c.darkened(0.3), 1.5)
	# Bones on top
	for b in _bones:
		match b["type"]:
			"long":
				# Shadow
				draw_line(b["a"] + Vector2(1, 1), b["b"] + Vector2(1, 1), bone_shadow, b["width"])
				# Bone shaft
				draw_line(b["a"], b["b"], bone_color, b["width"])
				# Bulbous caps
				draw_circle(b["a"], b["cap"], bone_color)
				draw_circle(b["b"], b["cap"], bone_color)
				draw_arc(b["a"], b["cap"], 0, TAU, 12, bone_shadow, 1.0)
				draw_arc(b["b"], b["cap"], 0, TAU, 12, bone_shadow, 1.0)
			"rib":
				draw_polyline(b["pts"], bone_shadow, b["width"] + 1.0)
				draw_polyline(b["pts"], bone_color, b["width"])
			"frag":
				draw_line(b["a"], b["b"], bone_color, b["width"])
				draw_circle(b["a"], b["width"] * 0.5, bone_color)
				draw_circle(b["b"], b["width"] * 0.5, bone_color)
			"dot":
				draw_circle(b["a"], b["width"], bone_shadow)
				draw_circle(b["a"], b["width"] * 0.8, bone_color)
			"skull":
				var p: Vector2 = b["pos"]
				var r: float = b["radius"]
				var a: float = b["angle"]
				# Skull circle
				draw_circle(p, r, bone_color)
				draw_arc(p, r, 0, TAU, 16, bone_shadow, 1.5)
				# Eye sockets
				var eye_off := r * 0.35
				var eye_r := r * 0.2
				var left_eye := p + Vector2(cos(a - 0.4) * eye_off, sin(a - 0.4) * eye_off)
				var right_eye := p + Vector2(cos(a + 0.4) * eye_off, sin(a + 0.4) * eye_off)
				draw_circle(left_eye, eye_r, Color(0.3, 0.25, 0.2))
				draw_circle(right_eye, eye_r, Color(0.3, 0.25, 0.2))
				# Snout hole
				var snout := p + Vector2(cos(a) * r * 0.55, sin(a) * r * 0.55)
				draw_circle(snout, eye_r * 0.7, Color(0.35, 0.3, 0.25))
