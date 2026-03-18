extends CharacterBody2D
## Neutral AI penguin — wanders the ice, eats fish, slides fast, light weight.
## Spawns by swimming in from the ocean.

const WALK_SPEED := 40.0        ## slow waddle
const SLIDE_SPEED := 507.0     ## fast slide burst
const SLIDE_FRICTION := 0.992  ## lighter friction — ~250px slide
const MAX_WANDER_SPEED := 900.0 ## uncapped for swim/leave (off-ice)
const RADIUS := 18.0
const ISO_H := 16.0   ## cylinder height in world-px
const FISH_DETECT_RANGE := 1000.0
const WANDER_CHANGE_TIME := 2.0
const ICE_CENTER := Vector2(960, 540)
const SLIDE_CHARGE_TIME := 3.0  ## seconds before first slide after choosing to slide

enum State { SWIMMING_IN, ACTIVE, LEAVING, IN_WATER }
enum MoveMode { WALKING, CHARGING, SLIDING, SLIDE_PAUSE }

var state: State = State.SWIMMING_IN
var _move_mode: MoveMode = MoveMode.WALKING
var _wander_dir := Vector2.ZERO
var _wander_timer := 0.0
var _mode_timer := 0.0     # multi-purpose timer for current mode
var _slide_dir := Vector2.ZERO
var _walk_duration := 0.0  # random walk duration before deciding to slide
var _rng := RandomNumberGenerator.new()
var _is_in_water := false  ## kept for arena compatibility
var _respawn_timer := 0.0
var _swim_target := Vector2.ZERO
var _leave_edge := Vector2.ZERO   ## open water edge point (on ice boundary)
var _leave_ocean := Vector2.ZERO  ## far ocean point (off-screen)
var _leaving_phase := 0           ## 0 = slide to edge, 1 = swim out
var _pause_timer := 0.0
var _has_fish := false

signal fish_stolen
signal fish_dropped(pos: Vector2)

func _ready() -> void:
	_rng.randomize()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	queue_redraw()
	_start_swim_in()

func _draw() -> void:
	# --- ISO 3D: shadow + cylinder side ---
	var shd_pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * i / 20.0
		shd_pts.append(Vector2(4.0 + cos(a) * (RADIUS + 2), RADIUS + ISO_H + 6.0 + sin(a) * 6.0))
	draw_colored_polygon(shd_pts, Color(0.0, 0.04, 0.10, 0.20))
	var seg := 20
	var side_pts := PackedVector2Array()
	for i in range(seg + 1):
		var a := PI * i / seg
		side_pts.append(Vector2(cos(a) * RADIUS * 0.8, sin(a) * RADIUS))
	for i in range(seg + 1):
		var a := PI * (seg - i) / seg
		side_pts.append(Vector2(cos(a) * RADIUS * 0.8, sin(a) * RADIUS + ISO_H))
	draw_colored_polygon(side_pts, Color(0.06, 0.06, 0.08))

	# Body — black oval
	var body_pts: PackedVector2Array = []
	for i in range(20):
		var angle := TAU * i / 20.0
		body_pts.append(Vector2(cos(angle) * RADIUS * 0.8, sin(angle) * RADIUS))
	draw_colored_polygon(body_pts, Color(0.1, 0.1, 0.12))

	# White belly
	var belly_pts: PackedVector2Array = []
	for i in range(16):
		var angle := TAU * i / 16.0
		belly_pts.append(Vector2(cos(angle) * RADIUS * 0.45, sin(angle) * RADIUS * 0.6))
	draw_colored_polygon(belly_pts, Color(0.95, 0.95, 0.97))

	# Eyes
	draw_circle(Vector2(-5, -RADIUS * 0.4), 3.0, Color.WHITE)
	draw_circle(Vector2(5, -RADIUS * 0.4), 3.0, Color.WHITE)
	draw_circle(Vector2(-5, -RADIUS * 0.4), 1.5, Color.BLACK)
	draw_circle(Vector2(5, -RADIUS * 0.4), 1.5, Color.BLACK)

	# Beak
	draw_colored_polygon([
		Vector2(0, -RADIUS * 0.15),
		Vector2(-4, -RADIUS * 0.35),
		Vector2(4, -RADIUS * 0.35),
	], Color(0.9, 0.6, 0.1))

	# Fish in beak
	if _has_fish:
		var fish_pos := Vector2(0, -RADIUS * 0.6)
		var fish_pts: PackedVector2Array = []
		for i in range(12):
			var angle := TAU * i / 12.0
			fish_pts.append(fish_pos + Vector2(cos(angle) * 8, sin(angle) * 5))
		draw_colored_polygon(fish_pts, Color(1.0, 0.65, 0.1))
		draw_colored_polygon([
			fish_pos + Vector2(7, 0),
			fish_pos + Vector2(12, -4),
			fish_pos + Vector2(12, 4),
		], Color(1.0, 0.65, 0.1))
		draw_circle(fish_pos + Vector2(-3, -2), 1.5, Color.BLACK)

func _physics_process(delta: float) -> void:
	match state:
		State.SWIMMING_IN:
			_process_swimming(delta)
		State.ACTIVE:
			_process_active(delta)
		State.LEAVING:
			_process_leaving(delta)
		State.IN_WATER:
			_respawn_timer -= delta
			if _respawn_timer <= 0.0:
				_start_swim_in()

func _process_swimming(_delta: float) -> void:
	# Tween handles movement — just check if we've arrived on ice
	var arena = get_parent()
	if arena and arena.has_method("_is_on_ice"):
		if arena._is_on_ice(global_position):
			_arrive_on_ice()

func _process_active(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity = Vector2.ZERO
		return

	match _move_mode:
		MoveMode.WALKING:
			_process_walking(delta)
		MoveMode.CHARGING:
			_process_charging(delta)
		MoveMode.SLIDING:
			_process_sliding(delta)
		MoveMode.SLIDE_PAUSE:
			_process_slide_pause(delta)

func _get_move_dir(delta: float) -> Vector2:
	var target := _find_nearest_fish()
	if target != null:
		return (target.global_position - global_position).normalized()
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_wander_dir()
	return _wander_dir

func _pick_next_mode() -> void:
	## If there's a target (fish, or exit when leaving), go straight to charge. Otherwise walk.
	var target := _find_nearest_fish()
	if target != null:
		_slide_dir = (target.global_position - global_position).normalized()
		_move_mode = MoveMode.CHARGING
		_mode_timer = SLIDE_CHARGE_TIME
	else:
		_move_mode = MoveMode.WALKING
		_mode_timer = _rng.randf_range(0.5, 2.0)

func _process_walking(delta: float) -> void:
	## Slow waddle — only when no slide target. Checks for fish each frame.
	_mode_timer -= delta
	# If a fish appears, switch to charge immediately
	var target := _find_nearest_fish()
	if target != null:
		_slide_dir = (target.global_position - global_position).normalized()
		_move_mode = MoveMode.CHARGING
		_mode_timer = SLIDE_CHARGE_TIME
		return

	var move_dir := _get_move_dir(delta)
	velocity = move_dir * WALK_SPEED

	var pre_velocity := velocity
	move_and_slide()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() is StaticBody2D:
			velocity = pre_velocity.bounce(col.get_normal()) * 0.5

	if _mode_timer <= 0.0:
		# No target found during walk — charge toward wander dir
		_move_mode = MoveMode.CHARGING
		_mode_timer = SLIDE_CHARGE_TIME
		_slide_dir = _wander_dir

func _process_charging(delta: float) -> void:
	## Waiting before slide — re-aim toward fish, creep slowly.
	_mode_timer -= delta
	# Keep updating aim toward fish during charge
	var target := _find_nearest_fish()
	if target != null:
		_slide_dir = (target.global_position - global_position).normalized()
	velocity = _slide_dir * WALK_SPEED * 0.5  # slow creep

	var pre_velocity := velocity
	move_and_slide()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() is StaticBody2D:
			velocity = pre_velocity.bounce(col.get_normal()) * 0.5

	if _mode_timer <= 0.0:
		# Launch slide
		_move_mode = MoveMode.SLIDING
		velocity = _slide_dir * SLIDE_SPEED

func _process_sliding(delta: float) -> void:
	## Fast slide with heavy friction — ~100px travel.
	velocity *= SLIDE_FRICTION
	if velocity.length() < 8.0:
		velocity = Vector2.ZERO
		# 1s pause, then can slide again in same direction
		_move_mode = MoveMode.SLIDE_PAUSE
		_mode_timer = 1.0
		return

	var pre_velocity := velocity
	move_and_slide()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() is StaticBody2D:
			velocity = pre_velocity.bounce(col.get_normal()) * 0.6

func _process_slide_pause(delta: float) -> void:
	## 1s pause between slides — re-aim toward fish, then slide again.
	_mode_timer -= delta
	velocity = Vector2.ZERO
	if _mode_timer <= 0.0:
		# If there's a target, slide again. Otherwise walk.
		var target := _find_nearest_fish()
		if target != null:
			_slide_dir = (target.global_position - global_position).normalized()
			_move_mode = MoveMode.SLIDING
			velocity = _slide_dir * SLIDE_SPEED
		else:
			_pick_next_mode()

## --- Swim in from ocean ---

func _start_swim_in() -> void:
	state = State.SWIMMING_IN
	_is_in_water = true
	visible = true
	scale = Vector2.ONE
	modulate.a = 1.0
	rotation = 0.0
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

	# Swim in through an open water edge
	var arena = get_parent()
	var from: Vector2
	_swim_target = ICE_CENTER
	if arena and arena.has_method("get_open_water_point"):
		var wp: Dictionary = arena.get_open_water_point()
		from = wp.ocean + (wp.ocean - wp.edge_mid).normalized() * 200.0
		_swim_target = wp.edge_mid + (ICE_CENTER - wp.edge_mid).normalized() * 40.0
	else:
		from = Vector2(-60, _rng.randf_range(150, 930))

	global_position = from

	var swim_duration := from.distance_to(_swim_target) / 100.0  # 50% swim speed
	swim_duration = clampf(swim_duration, 2.0, 8.0)

	var tw := create_tween()
	tw.tween_property(self, "global_position", _swim_target, swim_duration).set_ease(Tween.EASE_OUT)

	var tw2 := create_tween()
	var loops := int(swim_duration / 0.24)
	tw2.set_loops(maxi(loops, 2))
	tw2.tween_property(self, "rotation", 0.25, 0.12)
	tw2.tween_property(self, "rotation", -0.25, 0.12)

func _arrive_on_ice() -> void:
	state = State.ACTIVE
	_is_in_water = false
	rotation = 0.0
	velocity = Vector2.ZERO
	collision_layer = 2
	collision_mask = 1 | 2
	_pause_timer = 0.8  # brief stop after landing
	_pick_wander_dir()
	_pick_next_mode()
	var arena = get_parent()
	if arena and arena.has_method("_spawn_splash"):
		arena._spawn_splash(global_position, 3)  # PENGUIN_OUT

## --- Fall in water ---

func fall_in_water(how: String = "edge") -> void:
	if state == State.IN_WATER or state == State.SWIMMING_IN:
		return
	var arena = get_parent()
	if arena and arena.has_method("_spawn_splash"):
		arena._spawn_splash(global_position, 2)  # PENGUIN_IN
	# Penguin eats the fish — no drop
	if _has_fish:
		_has_fish = false
		queue_redraw()
		fish_stolen.emit()
	state = State.IN_WATER
	_is_in_water = true
	_respawn_timer = 3.5
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

	if how == "hole":
		_animate_sink()
	else:
		_animate_swim_away()

func _animate_sink() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.8).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_property(self, "rotation", TAU, 0.8)

func _animate_swim_away() -> void:
	var pos := global_position
	var swim_target: Vector2
	var dist_left := pos.x
	var dist_right := 1920.0 - pos.x
	var dist_top := pos.y
	var dist_bottom := 1080.0 - pos.y
	var min_dist := minf(minf(dist_left, dist_right), minf(dist_top, dist_bottom))
	if min_dist == dist_left:
		swim_target = Vector2(-80, pos.y + _rng.randf_range(-40, 40))
	elif min_dist == dist_right:
		swim_target = Vector2(2000, pos.y + _rng.randf_range(-40, 40))
	elif min_dist == dist_top:
		swim_target = Vector2(pos.x + _rng.randf_range(-40, 40), -80)
	else:
		swim_target = Vector2(pos.x + _rng.randf_range(-40, 40), 800)

	var tw := create_tween()
	tw.tween_property(self, "global_position", swim_target, 3.0).set_ease(Tween.EASE_IN_OUT)
	var tw2 := create_tween()
	tw2.set_loops(12)
	tw2.tween_property(self, "rotation", 0.3, 0.12)
	tw2.tween_property(self, "rotation", -0.3, 0.12)

## --- Helpers ---

func _find_nearest_fish() -> Node2D:
	var best: Node2D = null
	var best_dist := FISH_DETECT_RANGE
	for child in get_parent().get_children():
		if not child.has_method("start_jump"):
			continue
		if child.state != child.State.LANDED:
			continue
		var d := global_position.distance_to(child.global_position)
		if d < best_dist:
			best_dist = d
			best = child
	return best

func _pick_wander_dir() -> void:
	var angle := _rng.randf_range(0, TAU)
	_wander_dir = Vector2(cos(angle), sin(angle))
	_wander_timer = _rng.randf_range(1.0, WANDER_CHANGE_TIME)
	var to_center: Vector2 = (ICE_CENTER - global_position).normalized()
	_wander_dir = (_wander_dir + to_center * 0.5).normalized()

func collect_fish() -> void:
	_has_fish = true
	queue_redraw()
	_start_leaving()

func drop_fish() -> void:
	if not _has_fish:
		return
	_has_fish = false
	queue_redraw()
	fish_dropped.emit(global_position)
	# Cancel leaving — go back to active
	state = State.ACTIVE
	collision_layer = 2
	collision_mask = 1 | 2
	_pause_timer = 1.0  # stunned after being robbed
	_pick_next_mode()

func _start_leaving() -> void:
	state = State.LEAVING
	velocity = Vector2.ZERO
	_pause_timer = 0.6  # brief stop before leaving
	_leaving_phase = 0

	# Pick an open water edge — slide there first, then exit into ocean
	var arena = get_parent()
	if arena and arena.has_method("get_open_water_point"):
		var wp: Dictionary = arena.get_open_water_point()
		_leave_edge = wp.edge_mid
		_leave_ocean = wp.ocean + (wp.ocean - wp.edge_mid).normalized() * 200.0
	else:
		_leave_edge = Vector2(80, global_position.y)
		_leave_ocean = Vector2(-80, global_position.y)

func _process_leaving(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity = Vector2.ZERO
		if _pause_timer <= 0.0:
			var target := _leave_edge if _leaving_phase == 0 else _leave_ocean
			_slide_dir = (target - global_position).normalized()
			_move_mode = MoveMode.SLIDING
			velocity = _slide_dir * SLIDE_SPEED
		return

	var target := _leave_edge if _leaving_phase == 0 else _leave_ocean

	# Phase 0→1: reached open edge — disable wall collision, swim into ocean
	if _leaving_phase == 0 and global_position.distance_to(_leave_edge) < 50.0:
		_leaving_phase = 1
		set_deferred("collision_mask", 0)
		target = _leave_ocean
		_slide_dir = (target - global_position).normalized()
		_move_mode = MoveMode.SLIDING
		velocity = _slide_dir * SLIDE_SPEED

	# Slide→pause→slide toward current target, always re-aim
	match _move_mode:
		MoveMode.SLIDING:
			velocity *= SLIDE_FRICTION
			if velocity.length() < 8.0:
				velocity = Vector2.ZERO
				_move_mode = MoveMode.SLIDE_PAUSE
				_mode_timer = 1.0
		MoveMode.SLIDE_PAUSE:
			velocity = Vector2.ZERO
			_mode_timer -= delta
			if _mode_timer <= 0.0:
				_slide_dir = (target - global_position).normalized()
				_move_mode = MoveMode.SLIDING
				velocity = _slide_dir * SLIDE_SPEED
		_:
			_slide_dir = (target - global_position).normalized()
			_move_mode = MoveMode.SLIDING
			velocity = _slide_dir * SLIDE_SPEED

	move_and_slide()

	# Phase 1: reached ocean — despawn
	if _leaving_phase == 1 and global_position.distance_to(_leave_ocean) < 40:
		if _has_fish:
			_has_fish = false
			fish_stolen.emit()
		state = State.IN_WATER
		_is_in_water = true
		_respawn_timer = 4.0
		velocity = Vector2.ZERO
		visible = false
		set_deferred("collision_layer", 0)
