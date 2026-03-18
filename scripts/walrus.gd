extends CharacterBody2D
## Walrus — heavy aggressive enemy. Eats fish, furiously charges nearby seals/penguins.
## Can be bounced off ice by a fast seal hit (destroyed on leaving ice).

const SealScript := preload("res://scripts/seal.gd")
const PenguinScript := preload("res://scripts/penguin.gd")

const ACCEL := 900.0           ## px/s² — heavy, powerful acceleration
const MAX_SPEED := 320.0       ## px/s — normal movement cap
const FURY_SPEED := 420.0      ## px/s — speed cap when charging in fury
const FRICTION := 0.990        ## heavier friction than seal — stops more efficiently
const RADIUS := 40.0
const ISO_H := 24.0   ## cylinder height in world-px
const FURY_RADIUS := 250.0     ## px — aggression detection range
const FURY_COOLDOWN := 1.0     ## seconds target must stay outside radius to break lock
const POST_FURY_PAUSE := 1.0   ## seconds walrus pauses after fury ends
const FISH_DETECT_RANGE := 1500.0
const MAX_FISH := 3
const MASS := 3.0
const ICE_CENTER := Vector2(960, 540)

enum State { SWIMMING_IN, ACTIVE, LEAVING }
enum ActiveMode { HUNTING_FISH, FURY, COOLDOWN }

var state: State = State.SWIMMING_IN
var _active_mode: ActiveMode = ActiveMode.HUNTING_FISH
var _fury_target: CharacterBody2D = null
var _fury_escape_timer := 0.0
var _cooldown_timer := 0.0
var _fish_count := 0
var _wander_dir := Vector2.ZERO
var _wander_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _is_in_water := false
var _swim_target := Vector2.ZERO
var _leave_ocean := Vector2.ZERO
var _pause_timer := 0.0
var _bump_cooldown := 0.0
var _bounce_stun := 0.0
var _power_stun := 0.0

signal fish_stolen

func _ready() -> void:
	_rng.randomize()
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2
	queue_redraw()
	_start_swim_in()

func get_mass() -> float:
	return MASS

func _set_bounce_stun(t: float) -> void:
	_bounce_stun = t

func _set_bump_cooldown(t: float) -> void:
	_bump_cooldown = t

func _power_hit(impulse: Vector2, stun_time: float) -> void:
	velocity = impulse
	_power_stun = stun_time
	_fury_target = null
	_active_mode = ActiveMode.HUNTING_FISH
	queue_redraw()

## ============================================================
## State machine
## ============================================================

func _physics_process(delta: float) -> void:
	match state:
		State.SWIMMING_IN:
			_process_swimming(delta)
		State.ACTIVE:
			_process_active(delta)
		State.LEAVING:
			_process_leaving(delta)

func _process_active(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity = Vector2.ZERO
		return

	if _power_stun > 0.0:
		_power_stun -= delta
		velocity *= FRICTION
		if velocity.length() < 2.0:
			velocity = Vector2.ZERO
		move_and_slide()
		return

	if _bounce_stun > 0.0:
		_bounce_stun -= delta

	if _bump_cooldown > 0.0:
		_bump_cooldown -= delta

	# Sub-state logic (sets velocity via acceleration)
	match _active_mode:
		ActiveMode.HUNTING_FISH:
			_process_hunting(delta)
		ActiveMode.FURY:
			_process_fury(delta)
		ActiveMode.COOLDOWN:
			_process_cooldown(delta)

	# Speed cap
	var max_spd := FURY_SPEED if _active_mode == ActiveMode.FURY else MAX_SPEED
	if velocity.length() > max_spd:
		velocity = velocity.normalized() * max_spd

	velocity *= FRICTION
	if velocity.length() < 2.0:
		velocity = Vector2.ZERO

	var pre_velocity := velocity
	move_and_slide()
	_process_collisions(pre_velocity)

## ============================================================
## Active sub-states
## ============================================================

func _process_hunting(delta: float) -> void:
	# Priority 1: seal in fury radius
	var seal_target := _find_nearest_seal_in_fury()
	if seal_target:
		_enter_fury(seal_target)
		return
	# Priority 2: penguin in fury radius
	var pen_target := _find_nearest_penguin_in_fury()
	if pen_target:
		_enter_fury(pen_target)
		return
	# Priority 3: move toward nearest fish
	var fish := _find_nearest_fish()
	if fish:
		var dir := (fish.global_position - global_position).normalized()
		velocity += dir * ACCEL * delta
	else:
		# Wander
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_pick_wander_dir()
		velocity += _wander_dir * ACCEL * 0.3 * delta

func _process_fury(delta: float) -> void:
	# Target validity
	if not is_instance_valid(_fury_target) or _fury_target.get("_is_in_water") == true:
		_exit_fury()
		return

	# Priority upgrade: if chasing penguin and a seal enters fury radius, switch
	if _fury_target.get_script() == PenguinScript:
		var seal := _find_nearest_seal_in_fury()
		if seal:
			_fury_target = seal
			_fury_escape_timer = 0.0

	# Closer same-priority target transfer
	var dist := global_position.distance_to(_fury_target.global_position)
	if _fury_target.get_script() == SealScript:
		var closer := _find_nearest_seal_in_fury()
		if closer and closer != _fury_target:
			if global_position.distance_to(closer.global_position) < dist:
				_fury_target = closer
				_fury_escape_timer = 0.0
				dist = global_position.distance_to(closer.global_position)
	elif _fury_target.get_script() == PenguinScript:
		var closer := _find_nearest_penguin_in_fury()
		if closer and closer != _fury_target:
			if global_position.distance_to(closer.global_position) < dist:
				_fury_target = closer
				_fury_escape_timer = 0.0

	# Escape timer — target must stay outside fury radius for FURY_COOLDOWN
	if dist > FURY_RADIUS:
		_fury_escape_timer += delta
		if _fury_escape_timer >= FURY_COOLDOWN:
			_exit_fury()
			return
	else:
		_fury_escape_timer = 0.0

	# Charge toward target — aggressive acceleration
	var dir := (_fury_target.global_position - global_position).normalized()
	velocity += dir * ACCEL * 1.5 * delta

func _process_cooldown(delta: float) -> void:
	_cooldown_timer -= delta
	velocity = Vector2.ZERO
	if _cooldown_timer <= 0.0:
		_active_mode = ActiveMode.HUNTING_FISH

func _enter_fury(target: CharacterBody2D) -> void:
	_active_mode = ActiveMode.FURY
	_fury_target = target
	_fury_escape_timer = 0.0
	queue_redraw()

func _exit_fury() -> void:
	_fury_target = null
	_fury_escape_timer = 0.0
	_active_mode = ActiveMode.COOLDOWN
	_cooldown_timer = POST_FURY_PAUSE
	queue_redraw()

## ============================================================
## Collisions
## ============================================================

func _process_collisions(pre_velocity: Vector2) -> void:
	var speed := pre_velocity.length()
	var speed_factor := clampf(speed / 400.0, 0.05, 1.0)

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is CharacterBody2D and other != self:
			if _bump_cooldown > 0.0:
				continue
			var normal: Vector2 = (other.global_position - global_position).normalized()
			var is_penguin: bool = other.get_script() == PenguinScript

			if is_penguin:
				# Launch penguin hard — walrus plows through
				var launch := maxf(speed * 2.0, 200.0)
				other.velocity = normal * launch
				# Walrus barely slows down
				velocity = pre_velocity * 0.9
				_bump_cooldown = 0.15
			elif other.get_script() == SealScript:
				# Mass-based elastic collision
				var my_vel := pre_velocity
				var other_vel: Vector2 = other.velocity
				var my_along: float = my_vel.dot(normal)
				var other_along: float = other_vel.dot(normal)
				var damping := 0.8 * speed_factor
				var m1 := MASS
				var m2 := 1.0
				if other.has_method("get_mass"):
					m2 = other.get_mass()
				var m_total := m1 + m2
				var w1 := 2.0 * m2 / m_total
				var w2 := 2.0 * m1 / m_total
				velocity = my_vel - normal * my_along * w1 + normal * (other_along * damping * w1)
				other.velocity = other_vel - normal * other_along * w2 + normal * (my_along * damping * w2)
				_bounce_stun = 0.15 * speed_factor
				if other.has_method("_set_bounce_stun"):
					other._set_bounce_stun(0.2 * speed_factor)
				_bump_cooldown = 0.15
				if other.has_method("_set_bump_cooldown"):
					other._set_bump_cooldown(0.15)
				# Powerful hit knocks fish loose from seal
				if speed_factor > 0.4 and other.has_method("drop_fish") and other.get("_has_fish"):
					other.drop_fish()
		elif other is StaticBody2D:
			var impact := absf(pre_velocity.dot(col.get_normal()))
			if impact > 50.0:
				velocity = pre_velocity.bounce(col.get_normal()) * 0.7

## ============================================================
## Swim in
## ============================================================

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

	var arena = get_parent()
	var from: Vector2
	_swim_target = ICE_CENTER
	if arena and arena.has_method("get_open_water_point"):
		var wp: Dictionary = arena.get_open_water_point()
		from = wp.ocean + (wp.ocean - wp.edge_mid).normalized() * 220.0
		_swim_target = wp.edge_mid + (ICE_CENTER - wp.edge_mid).normalized() * 50.0
	else:
		from = Vector2(-80, _rng.randf_range(150, 930))

	global_position = from
	var swim_duration := from.distance_to(_swim_target) / 120.0
	swim_duration = clampf(swim_duration, 2.0, 6.0)

	var tw := create_tween()
	tw.tween_property(self, "global_position", _swim_target, swim_duration).set_ease(Tween.EASE_OUT)

func _process_swimming(_delta: float) -> void:
	var arena = get_parent()
	if arena and arena.has_method("_is_on_ice"):
		if arena._is_on_ice(global_position):
			_arrive_on_ice()

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
		arena._spawn_splash(global_position, 5)  # reuse BEAR_OUT splash

## ============================================================
## Leaving (after eating MAX_FISH)
## ============================================================

func _start_leaving() -> void:
	state = State.LEAVING
	_fury_target = null
	_active_mode = ActiveMode.HUNTING_FISH
	velocity = Vector2.ZERO
	_pause_timer = 1.0

	var arena = get_parent()
	if arena and arena.has_method("get_open_water_point"):
		var wp: Dictionary = arena.get_open_water_point()
		_leave_ocean = wp.ocean + (wp.ocean - wp.edge_mid).normalized() * 200.0
	else:
		_leave_ocean = Vector2(-80, global_position.y)

func _process_leaving(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity = Vector2.ZERO
		if _pause_timer <= 0.0:
			set_deferred("collision_mask", 0)
			var arena = get_parent()
			if arena and arena.has_method("_spawn_splash"):
				arena._spawn_splash(global_position, 4)  # reuse BEAR_IN
		return

	var dir: Vector2 = (_leave_ocean - global_position).normalized()
	velocity += dir * ACCEL * 0.6 * delta
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED
	velocity *= FRICTION
	move_and_slide()

	if global_position.distance_to(_leave_ocean) < 40:
		queue_free()

## ============================================================
## Fish eating
## ============================================================

func collect_fish() -> void:
	if _fish_count >= MAX_FISH:
		return
	_fish_count += 1
	fish_stolen.emit()
	queue_redraw()
	if _fish_count >= MAX_FISH:
		_start_leaving()

## ============================================================
## Helpers
## ============================================================

func _find_nearest_seal_in_fury() -> CharacterBody2D:
	var best: CharacterBody2D = null
	var best_dist := FURY_RADIUS
	for child in get_parent().get_children():
		if child == self or not child is CharacterBody2D:
			continue
		if child.get_script() != SealScript:
			continue
		if child.get("_is_in_water") == true:
			continue
		var d := global_position.distance_to(child.global_position)
		if d < best_dist:
			best_dist = d
			best = child
	return best

func _find_nearest_penguin_in_fury() -> CharacterBody2D:
	var best: CharacterBody2D = null
	var best_dist := FURY_RADIUS
	for child in get_parent().get_children():
		if child == self or not child is CharacterBody2D:
			continue
		if child.get_script() != PenguinScript:
			continue
		if child.get("_is_in_water") == true:
			continue
		if child.get("state") != 1:  # State.ACTIVE
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

## ============================================================
## Drawing
## ============================================================

func _draw() -> void:
	# --- ISO 3D: shadow + cylinder side ---
	var shd_pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * i / 20.0
		shd_pts.append(Vector2(6.0 + cos(a) * (RADIUS + 4), RADIUS + ISO_H + 8.0 + sin(a) * 11.0))
	draw_colored_polygon(shd_pts, Color(0.0, 0.03, 0.08, 0.22))
	var seg := 20
	var side_pts := PackedVector2Array()
	for i in range(seg + 1):
		var a := PI * i / seg
		side_pts.append(Vector2(cos(a) * RADIUS, sin(a) * RADIUS * 0.85))
	for i in range(seg + 1):
		var a := PI * (seg - i) / seg
		side_pts.append(Vector2(cos(a) * RADIUS, sin(a) * RADIUS * 0.85 + ISO_H))
	draw_colored_polygon(side_pts, Color(0.38, 0.27, 0.19))

	# Body — large brown oval
	var body_pts: PackedVector2Array = []
	for i in range(24):
		var angle := TAU * i / 24.0
		body_pts.append(Vector2(cos(angle) * RADIUS, sin(angle) * RADIUS * 0.85))
	draw_colored_polygon(body_pts, Color(0.55, 0.40, 0.30))
	draw_polyline(body_pts, Color(0.40, 0.28, 0.18), 2.0)

	# Lighter belly
	var belly_pts: PackedVector2Array = []
	for i in range(16):
		var angle := TAU * i / 16.0
		belly_pts.append(Vector2(cos(angle) * RADIUS * 0.5, sin(angle) * RADIUS * 0.4 + 6))
	draw_colored_polygon(belly_pts, Color(0.65, 0.52, 0.42))

	# Eyes — small, beady
	draw_circle(Vector2(-10, -RADIUS * 0.3), 4.0, Color.BLACK)
	draw_circle(Vector2(10, -RADIUS * 0.3), 4.0, Color.BLACK)
	draw_circle(Vector2(-10, -RADIUS * 0.3), 1.5, Color(0.3, 0.3, 0.3))
	draw_circle(Vector2(10, -RADIUS * 0.3), 1.5, Color(0.3, 0.3, 0.3))

	# Snout — broad
	draw_circle(Vector2(0, RADIUS * 0.05), 12.0, Color(0.50, 0.38, 0.28))
	# Nose
	draw_circle(Vector2(0, -2), 4.0, Color(0.2, 0.15, 0.12))
	# Whisker dots
	for dx in [-8.0, -5.0, 5.0, 8.0]:
		draw_circle(Vector2(dx, 6), 1.5, Color(0.35, 0.25, 0.18))

	# Tusks
	var tusk_color := Color(0.95, 0.92, 0.85)
	draw_line(Vector2(-6, 8), Vector2(-8, 22), tusk_color, 3.0)
	draw_line(Vector2(6, 8), Vector2(8, 22), tusk_color, 3.0)
	draw_circle(Vector2(-8, 22), 2.0, tusk_color)
	draw_circle(Vector2(8, 22), 2.0, tusk_color)

	# Fury indicator — red glow ring when in fury mode
	if _active_mode == ActiveMode.FURY:
		draw_arc(Vector2.ZERO, RADIUS + 4, 0, TAU, 20, Color(1.0, 0.2, 0.1, 0.5), 3.0)

	# Carried fish on back
	for fi in _fish_count:
		var fx := -16.0 + fi * 16.0
		_draw_carried_fish(Vector2(fx, -RADIUS - 8))

func _draw_carried_fish(fp: Vector2) -> void:
	draw_circle(fp + Vector2(2, 0), 12.0, Color(1.0, 0.8, 0.2, 0.25))
	var fish_pts: PackedVector2Array = []
	for fi in range(12):
		var angle := TAU * fi / 12.0
		fish_pts.append(fp + Vector2(cos(angle) * 9, sin(angle) * 5))
	draw_colored_polygon(fish_pts, Color(1.0, 0.65, 0.1))
	draw_polyline(fish_pts, Color(0.8, 0.4, 0.0), 1.5)
	draw_colored_polygon([fp + Vector2(7, 0), fp + Vector2(12, -4), fp + Vector2(12, 4)], Color(1.0, 0.6, 0.05))
	draw_circle(fp + Vector2(-3, -1), 1.5, Color.WHITE)
	draw_circle(fp + Vector2(-3, -1), 0.8, Color.BLACK)
