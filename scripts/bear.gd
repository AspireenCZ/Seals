extends CharacterBody2D
## Polar bear — giant, slow, deadly. Swims in, collects 5 fish, swims away.

const ACCEL := 300.0
const MAX_SPEED := 180.0
const FRICTION := 0.994
const RADIUS := 50.0
const FISH_DETECT_RANGE := 2000.0
const PLAYER_HUNT_RANGE := 300.0
const MAX_FISH := 5
const ICE_CENTER := Vector2(960, 540)

enum State { SWIMMING_IN, ACTIVE, LEAVING, GONE }

var state: State = State.SWIMMING_IN
var _fish_count := 0
var _wander_dir := Vector2.ZERO
var _wander_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _swim_target := Vector2.ZERO
var _leave_target := Vector2.ZERO
var _is_in_water := true
var _pause_timer := 0.0

signal fish_stolen

func _ready() -> void:
	_rng.randomize()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2
	queue_redraw()
	_start_swim_in()

func _draw() -> void:
	# Body — large white circle
	draw_circle(Vector2.ZERO, RADIUS, Color(0.95, 0.95, 0.93))
	# Outline
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, Color(0.7, 0.7, 0.65), 2.5)

	# Ears
	draw_circle(Vector2(-RADIUS * 0.6, -RADIUS * 0.65), 12.0, Color(0.9, 0.88, 0.85))
	draw_circle(Vector2(RADIUS * 0.6, -RADIUS * 0.65), 12.0, Color(0.9, 0.88, 0.85))
	draw_circle(Vector2(-RADIUS * 0.6, -RADIUS * 0.65), 7.0, Color(0.75, 0.6, 0.55))
	draw_circle(Vector2(RADIUS * 0.6, -RADIUS * 0.65), 7.0, Color(0.75, 0.6, 0.55))

	# Eyes — small, menacing
	draw_circle(Vector2(-12, -RADIUS * 0.25), 4.0, Color.BLACK)
	draw_circle(Vector2(12, -RADIUS * 0.25), 4.0, Color.BLACK)
	draw_circle(Vector2(-12, -RADIUS * 0.25), 1.5, Color(0.3, 0.3, 0.3))
	draw_circle(Vector2(12, -RADIUS * 0.25), 1.5, Color(0.3, 0.3, 0.3))

	# Nose
	draw_circle(Vector2(0, RADIUS * 0.05), 6.0, Color(0.15, 0.15, 0.15))

	# Muzzle
	draw_circle(Vector2(0, RADIUS * 0.15), 14.0, Color(0.92, 0.92, 0.9))

	# Carried fish — stacked on back
	for i in _fish_count:
		var fx := -24.0 + i * 12.0
		var fy := -RADIUS - 10.0 - i * 4.0
		_draw_carried_fish(Vector2(fx, fy))

func _draw_carried_fish(fp: Vector2) -> void:
	draw_circle(fp + Vector2(2, 0), 14.0, Color(1.0, 0.8, 0.2, 0.25))
	var fish_pts: PackedVector2Array = []
	for fi in range(16):
		var angle := TAU * fi / 16.0
		fish_pts.append(fp + Vector2(cos(angle) * 10, sin(angle) * 6))
	draw_colored_polygon(fish_pts, Color(1.0, 0.65, 0.1))
	draw_polyline(fish_pts, Color(0.8, 0.4, 0.0), 1.5)
	draw_colored_polygon([fp + Vector2(8, 0), fp + Vector2(14, -5), fp + Vector2(14, 5)], Color(1.0, 0.6, 0.05))
	draw_circle(fp + Vector2(-3, -1), 1.5, Color.WHITE)
	draw_circle(fp + Vector2(-3, -1), 0.8, Color.BLACK)

func _physics_process(delta: float) -> void:
	match state:
		State.SWIMMING_IN:
			_process_swimming(delta)
		State.ACTIVE:
			_process_active(delta)
		State.LEAVING:
			_process_leaving(delta)

func _process_swimming(_delta: float) -> void:
	var arena = get_parent()
	if arena and arena.has_method("_is_on_ice"):
		if arena._is_on_ice(global_position):
			_arrive_on_ice()

func _process_active(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity = Vector2.ZERO
		return
	var fish_target := _find_nearest_fish()
	var player_target := _find_nearest_player()

	if fish_target != null and _fish_count < MAX_FISH:
		# Prioritize fish (only if not full)
		var dir: Vector2 = (fish_target.global_position - global_position).normalized()
		velocity += dir * ACCEL * delta
	elif player_target != null:
		# Hunt nearby players
		var dir: Vector2 = (player_target.global_position - global_position).normalized()
		velocity += dir * ACCEL * 0.8 * delta
	else:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_pick_wander_dir()
		velocity += _wander_dir * ACCEL * 0.3 * delta

	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED

	velocity *= FRICTION

	if velocity.length() < 2.0:
		velocity = Vector2.ZERO

	var pre_velocity := velocity
	move_and_slide()

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is StaticBody2D:
			var normal: Vector2 = col.get_normal()
			velocity = pre_velocity.bounce(normal) * 0.4
		elif other is CharacterBody2D and other != self:
			# Bear is a wall — barely affected
			velocity *= 0.95

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
		from = wp.ocean + (wp.ocean - wp.edge_mid).normalized() * 250.0
		_swim_target = wp.edge_mid + (ICE_CENTER - wp.edge_mid).normalized() * 50.0
	else:
		from = Vector2(-80, _rng.randf_range(150, 930))

	global_position = from

	var swim_duration := from.distance_to(_swim_target) / 150.0
	swim_duration = clampf(swim_duration, 2.0, 6.0)

	var tw := create_tween()
	tw.tween_property(self, "global_position", _swim_target, swim_duration).set_ease(Tween.EASE_OUT)

func _arrive_on_ice() -> void:
	state = State.ACTIVE
	_is_in_water = false
	velocity = Vector2.ZERO
	collision_layer = 2
	collision_mask = 1 | 2
	_pause_timer = 1.0
	_pick_wander_dir()
	var arena = get_parent()
	if arena and arena.has_method("_spawn_splash"):
		arena._spawn_splash(global_position, 5)  # BEAR_OUT

## --- Leaving ---

func _start_leaving() -> void:
	state = State.LEAVING
	velocity = Vector2.ZERO
	_pause_timer = 1.0
	# Disable wall collision only after pause (deferred to _process_leaving)

	# Leave through an open water edge
	var arena = get_parent()
	if arena and arena.has_method("get_open_water_point"):
		var wp: Dictionary = arena.get_open_water_point()
		_leave_target = wp.ocean + (wp.ocean - wp.edge_mid).normalized() * 250.0
	else:
		_leave_target = Vector2(-120, global_position.y)

func _process_leaving(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity = Vector2.ZERO
		if _pause_timer <= 0.0:
			set_deferred("collision_mask", 0)  # disable walls after pause
			# Splash as bear enters water
			var arena = get_parent()
			if arena and arena.has_method("_spawn_splash"):
				arena._spawn_splash(global_position, 4)  # BEAR_IN
		return
	var dir: Vector2 = (_leave_target - global_position).normalized()
	velocity += dir * ACCEL * 0.6 * delta

	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED

	velocity *= FRICTION
	move_and_slide()

	if global_position.distance_to(_leave_target) < 40:
		state = State.GONE
		visible = false
		set_deferred("collision_layer", 0)

## --- Fish eating ---

func collect_fish() -> void:
	if _fish_count >= MAX_FISH:
		return
	_fish_count += 1
	fish_stolen.emit()
	queue_redraw()
	if _fish_count >= MAX_FISH:
		_start_leaving()

## --- Deadly to players ---

func is_deadly() -> bool:
	return state == State.ACTIVE

## --- Helpers ---

func _find_nearest_player() -> Node2D:
	var best: Node2D = null
	var best_dist := PLAYER_HUNT_RANGE
	for child in get_parent().get_children():
		if not child.has_method("fall_in_water"):
			continue
		if not "player_index" in child:
			continue
		if child._is_in_water:
			continue
		var d := global_position.distance_to(child.global_position)
		if d < best_dist:
			best_dist = d
			best = child
	return best

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
	_wander_timer = _rng.randf_range(1.5, 3.0)
	var to_center: Vector2 = (ICE_CENTER - global_position).normalized()
	_wander_dir = (_wander_dir + to_center * 0.4).normalized()
