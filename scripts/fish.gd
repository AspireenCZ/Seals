extends Area2D
## A fish that jumps from water onto ice and becomes collectible.

enum State { JUMPING, LANDED, COLLECTED }

var state: State = State.JUMPING
var origin := "ground"  ## "ground" or "opponent" — set by arena when spawned from drop
var _arc_start: Vector2
var _arc_end: Vector2
var _arc_time := 0.0
var _arc_duration := 0.6
var _arc_height := 80.0
var _landed_lifetime := 8.0  ## disappears if not collected

const FISH_SIZE := Vector2(28, 18)

func _ready() -> void:
	# Collision shape added in code
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = FISH_SIZE * 1.5
	shape.shape = rect
	add_child(shape)

	body_entered.connect(_on_body_entered)
	# Start monitoring only after landing
	monitoring = false
	monitorable = true
	collision_layer = 4   # fish layer
	collision_mask = 2    # player layer
	queue_redraw()

func _draw() -> void:
	if state == State.COLLECTED:
		return
	# ISO 3D: flat shadow when landed
	if state == State.LANDED:
		var shd_pts := PackedVector2Array()
		for i in range(16):
			var a := TAU * i / 16.0
			shd_pts.append(Vector2(3.0 + cos(a) * (FISH_SIZE.x * 0.6), FISH_SIZE.y * 0.35 + 8.0 + sin(a) * 5.0))
		draw_colored_polygon(shd_pts, Color(0.0, 0.04, 0.10, 0.18))
	var c := Color(1.0, 0.65, 0.1) if state == State.LANDED else Color(1, 0.6, 0, 0.5)
	var outline_c := Color(0.7, 0.35, 0.0) if state == State.LANDED else Color(0.5, 0.3, 0, 0.4)
	# Body ellipse
	var pts: PackedVector2Array = []
	for i in range(20):
		var angle := TAU * i / 20.0
		pts.append(Vector2(cos(angle) * FISH_SIZE.x * 0.5, sin(angle) * FISH_SIZE.y * 0.5))
	draw_colored_polygon(pts, c)
	# Body outline
	draw_polyline(pts, outline_c, 2.0)
	# Tail
	var tx := FISH_SIZE.x * 0.4
	draw_colored_polygon([Vector2(tx, 0), Vector2(tx + 10, -7), Vector2(tx + 10, 7)], c)
	# Eye
	draw_circle(Vector2(-FISH_SIZE.x * 0.15, -3), 3.0, Color.WHITE)
	draw_circle(Vector2(-FISH_SIZE.x * 0.15, -3), 1.5, Color.BLACK)
	# Landed glow indicator
	if state == State.LANDED:
		draw_arc(Vector2.ZERO, FISH_SIZE.x * 0.55, 0, TAU, 20, Color(1, 0.9, 0.3, 0.4), 2.0)

## Set up the jump arc. Call right after instantiation.
func start_jump(from: Vector2, to: Vector2, duration := 0.6, height := 80.0) -> void:
	_arc_start = from
	_arc_end = to
	_arc_duration = duration
	_arc_height = height
	_arc_time = 0.0
	global_position = from
	state = State.JUMPING

func _process(delta: float) -> void:
	match state:
		State.JUMPING:
			_arc_time += delta
			var t := clampf(_arc_time / _arc_duration, 0.0, 1.0)
			var pos := _arc_start.lerp(_arc_end, t)
			# Parabolic height
			pos.y -= _arc_height * 4.0 * t * (1.0 - t)
			global_position = pos
			# Scale for fake perspective
			scale = Vector2.ONE * lerpf(0.5, 1.0, t)
			if t >= 1.0:
				_land()
		State.LANDED:
			_landed_lifetime -= delta
			if _landed_lifetime <= 0.0:
				queue_free()
			# Flop animation
			rotation = sin(Time.get_ticks_msec() * 0.005) * 0.15

func _land() -> void:
	state = State.LANDED
	global_position = _arc_end
	scale = Vector2.ONE
	monitoring = true
	# Splash effect — just a brief scale pop
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.3, 0.7), 0.1)
	tw.tween_property(self, "scale", Vector2.ONE, 0.15)
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if state != State.LANDED:
		return
	if body.has_method("collect_fish"):
		# Check if seal can accept fish (not in water, not flashing, not full)
		if "_fish_count" in body and body._fish_count >= body.MAX_FISH:
			return
		if "_is_in_water" in body and body._is_in_water:
			return
		if "_flash_timer" in body and body._flash_timer > 0.0:
			return
		state = State.COLLECTED
		# For opponent-dropped fish, override the origin after collect
		if origin == "opponent" and "_fish_origins" in body:
			body.collect_fish()
			# Replace the last-added "ground" origin with "opponent"
			if body._fish_origins.size() > 0:
				body._fish_origins[-1] = "opponent"
		else:
			body.collect_fish()
		# Pop effect
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
		tw.tween_property(self, "modulate:a", 0.0, 0.15)
		tw.tween_callback(queue_free)
		queue_redraw()
