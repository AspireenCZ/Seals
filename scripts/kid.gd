extends Node2D
## Baby seal — collect fish and bring them here to feed your kid.
## Wanders on ice, reacts to nearby parent and bear.

var player_index: int = 0
var body_color: Color = Color.CORNFLOWER_BLUE
var fish_fed: int = 0

## Wandering
var _wander_dir := Vector2.RIGHT
var _wander_timer := 3.0
const WANDER_SPEED := 40.0
const PANIC_SPEED := 70.0
var _bounce_vel := Vector2.ZERO
var _panicking := false

## Animation
var _waddle_phase := 0.0
var _look_phase := 0.0
var _chomp_timer := 0.0
var _feed_pop := 0.0
var _is_scared := false
var _tremble := Vector2.ZERO
var _parent_near := false

## Promotion (kid → adult on win)
var promoted := false
var _promote_timer := 0.0

## Flee to water
var in_water := false
var _water_timer := 0.0
const FLEE_DISTANCE := 150.0
const PANIC_DISTANCE := 600.0
const WATER_HIDE_TIME := 5.0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_wander_timer = _rng.randf_range(2.0, 4.0)
	_wander_dir = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()

func _process(delta: float) -> void:
	var arena := get_parent()
	if in_water:
		_water_timer -= delta
		if _water_timer <= 0.0:
			_emerge(arena)
		return
	_update_wander(arena, delta)
	_update_animations(arena, delta)
	_check_flee(arena)
	if not in_water:
		_try_eat_fish(arena)
	queue_redraw()

func _update_wander(arena: Node2D, delta: float) -> void:
	# When panicking, _check_flee sets direction — skip normal target picking
	if not _panicking:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			var target: Vector2
			var roll := _rng.randf()
			if roll < 0.60:
				target = _pick_water_target(arena)
			elif roll < 0.85:
				target = _pick_parent_target(arena)
			else:
				target = arena._random_point_on_ice()
			_wander_dir = (target - position).normalized()
			_wander_timer = _rng.randf_range(4.0, 8.0)
	# Apply bounce velocity (decays with friction)
	if _bounce_vel.length() > 5.0:
		_bounce_vel *= 0.92
		var bounce_pos: Vector2 = position + _bounce_vel * delta
		if arena._is_safe_spot(bounce_pos, 30.0):
			position = bounce_pos
		else:
			_bounce_vel = Vector2.ZERO
	var speed := PANIC_SPEED if _panicking else WANDER_SPEED
	var new_pos: Vector2 = position + _wander_dir * speed * delta
	if arena._is_safe_spot(new_pos, 25.0):
		position = new_pos
	elif not arena._is_on_ice(new_pos):
		# Walked into water (hole or off-ice) — dive and respawn
		_dive(arena)
	else:
		# Near edge/hole but still on ice — turn away
		var away: Vector2 = (position - arena._nearest_polygon_edge_point(position, arena.ice_polygon)).normalized()
		position += away * 3.0
		_wander_dir = (arena.ICE_CENTER - position).normalized()
		_wander_timer = _rng.randf_range(1.0, 2.0)

func _pick_water_target(arena: Node2D) -> Vector2:
	## Pick a point near an open water edge or ice hole.
	var open_edges: Array[int] = []
	for idx in range(arena.ice_polygon.size()):
		if idx not in arena.wall_edge_indices:
			open_edges.append(idx)
	var has_holes: bool = arena.ice_holes.size() > 0

	# Sometimes target a hole instead of edge
	if has_holes and (open_edges.is_empty() or _rng.randf() < 0.4):
		var hole: PackedVector2Array = arena.ice_holes[_rng.randi() % arena.ice_holes.size()]
		var hc: Vector2 = arena._polygon_center(hole)
		var angle := _rng.randf() * TAU
		var target: Vector2 = hc + Vector2(cos(angle), sin(angle)) * _rng.randf_range(80, 130)
		if arena._is_safe_spot(target, 50.0):
			return target

	# Target a point near an open water edge
	if not open_edges.is_empty():
		var idx: int = open_edges[_rng.randi() % open_edges.size()]
		var next_idx: int = (idx + 1) % arena.ice_polygon.size()
		var edge_pt: Vector2 = arena.ice_polygon[idx].lerp(arena.ice_polygon[next_idx], _rng.randf_range(0.2, 0.8))
		var inward: Vector2 = (arena.ICE_CENTER - edge_pt).normalized()
		var target: Vector2 = edge_pt + inward * _rng.randf_range(60, 100)
		if arena._is_safe_spot(target, 50.0):
			return target

	return arena._random_point_on_ice()

func _pick_parent_target(arena: Node2D) -> Vector2:
	## Point biased toward parent — gentle drift, not a chase.
	if player_index >= arena.players.size():
		return _pick_water_target(arena)
	var pw: CharacterBody2D = arena.players[player_index]
	var target := position.lerp(pw.global_position, _rng.randf_range(0.3, 0.5))
	target += Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40))
	if arena._is_safe_spot(target, 50.0):
		return target
	return _pick_water_target(arena)

func _try_eat_fish(arena: Node2D) -> void:
	## Eat a nearby landed fish — scores a point directly.
	for child in arena.get_children():
		if not (child is Area2D) or not child.has_method("start_jump"):
			continue
		if child.get("state") != 1:  # Fish.State.LANDED
			continue
		if child.global_position.distance_to(global_position) < 70.0:
			child.state = 2  # Fish.State.COLLECTED
			feed()
			arena.scores[player_index] += 1
			arena._update_ui()
			arena._score_pop(player_index, 1)
			var tw := child.create_tween()
			tw.tween_property(child, "scale", Vector2(1.5, 1.5), 0.1)
			tw.tween_property(child, "modulate:a", 0.0, 0.15)
			tw.tween_callback(child.queue_free)
			child.queue_redraw()
			return

func _check_flee(arena: Node2D) -> void:
	## Dive into water when enemy gets too close, or panic-run on land.
	var nearest_bear: Node2D = null
	var nearest_dist := INF
	for bear in arena._bears:
		if is_instance_valid(bear):
			var d: float = bear.global_position.distance_to(global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest_bear = bear
	if nearest_bear == null or nearest_dist > PANIC_DISTANCE:
		_panicking = false
		return
	# Close enough + near water → dive
	if nearest_dist < FLEE_DISTANCE and _is_near_water(arena):
		_dive(arena)
		return
	# Within panic range → run away on land
	_panicking = true
	var away: Vector2 = (global_position - nearest_bear.global_position).normalized()
	# Bias toward nearest water when fleeing
	var water_dir: Vector2 = (_nearest_water_point(arena) - global_position).normalized()
	_wander_dir = (away + water_dir * 0.5).normalized()
	_wander_timer = 0.5  # re-evaluate direction frequently

func _nearest_water_point(arena: Node2D) -> Vector2:
	## Find closest open water edge or hole center for flee biasing.
	var best_pos := global_position
	var best_dist := INF
	# Check holes
	for hole in arena.ice_holes:
		var hc: Vector2 = arena._polygon_center(hole)
		var d: float = global_position.distance_to(hc)
		if d < best_dist:
			best_dist = d
			best_pos = hc
	# Check open water edges
	for idx in range(arena.ice_polygon.size()):
		if idx in arena.wall_edge_indices:
			continue
		var next_idx: int = (idx + 1) % arena.ice_polygon.size()
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(global_position, arena.ice_polygon[idx], arena.ice_polygon[next_idx])
		var d: float = global_position.distance_to(closest)
		if d < best_dist:
			best_dist = d
			best_pos = closest
	return best_pos

func _is_near_water(arena: Node2D) -> bool:
	## True if kid is close to an open water edge or ice hole.
	# Check holes
	for hole in arena.ice_holes:
		var hc: Vector2 = arena._polygon_center(hole)
		if global_position.distance_to(hc) < 150.0:
			return true
	# Check open water edges
	for idx in range(arena.ice_polygon.size()):
		if idx in arena.wall_edge_indices:
			continue
		var next_idx: int = (idx + 1) % arena.ice_polygon.size()
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(global_position, arena.ice_polygon[idx], arena.ice_polygon[next_idx])
		if global_position.distance_to(closest) < 120.0:
			return true
	return false

func _dive(arena: Node2D) -> void:
	var water_pos: Vector2 = _nearest_water_point(arena)
	# Push ripple further into the water so it doesn't overlap ice
	var outward: Vector2 = (water_pos - arena.ICE_CENTER).normalized()
	var ripple_pos: Vector2 = water_pos + outward * 40.0
	in_water = true
	visible = false
	_water_timer = WATER_HIDE_TIME
	if arena.has_method("_spawn_splash"):
		arena._spawn_splash(water_pos, 2)  # PENGUIN_IN (small splash)
	_spawn_dive_ripple(arena, ripple_pos)

func _emerge(arena: Node2D) -> void:
	## Resurface at safest water-adjacent spot, farthest from enemies.
	var best_pos := position
	var best_score := -1.0
	for _attempt in range(12):
		var candidate := _pick_water_target(arena)
		var min_dist := _min_enemy_distance(arena, candidate)
		if min_dist > best_score:
			best_score = min_dist
			best_pos = candidate
	position = best_pos
	in_water = false
	visible = true
	if arena.has_method("_spawn_splash"):
		arena._spawn_splash(global_position, 3)  # PENGUIN_OUT (small splash)

func _min_enemy_distance(arena: Node2D, pos: Vector2) -> float:
	var min_dist := INF
	for bear in arena._bears:
		if is_instance_valid(bear):
			min_dist = minf(min_dist, bear.global_position.distance_to(pos))
	return min_dist

func _update_animations(arena: Node2D, delta: float) -> void:
	# Parent proximity — perk up when carrying fish
	_parent_near = false
	if player_index < arena.players.size():
		var pw: CharacterBody2D = arena.players[player_index]
		if pw.global_position.distance_to(global_position) < 180.0 and pw._has_fish:
			_parent_near = true
	# Waddle — faster/wider when excited
	var waddle_speed := 12.0 if _parent_near else 8.0
	var waddle_amp := 12.0 if _parent_near else 8.0
	_waddle_phase += delta * waddle_speed
	rotation = sin(_waddle_phase) * deg_to_rad(waddle_amp)
	# Head idle look
	_look_phase += delta
	# Chomp
	if _chomp_timer > 0.0:
		_chomp_timer -= delta
	# Feed pop
	if _feed_pop > 0.0:
		_feed_pop = maxf(0.0, _feed_pop - delta * 3.0)
	# Bear scare
	_is_scared = false
	_tremble = Vector2.ZERO
	for bear in arena._bears:
		if is_instance_valid(bear) and bear.global_position.distance_to(global_position) < PANIC_DISTANCE:
			_is_scared = true
			_tremble = Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 1.0))
			break
	# Promote animation — grow to adult size
	if _promote_timer > 0.0:
		_promote_timer -= delta
	# Scale: growth + pop + scared squash + promotion
	var growth: float = 1.0 + 0.2 * (float(fish_fed) / 10.0)
	if promoted:
		var t: float = clampf(1.0 - _promote_timer / 0.6, 0.0, 1.0)
		growth = lerpf(growth, 1.0, t)
	var pop: float = 1.0 + _feed_pop * 0.15
	var sy: float = 0.85 if _is_scared else 1.0
	scale = Vector2(growth * pop, growth * pop * sy)

func bounce(impulse: Vector2) -> void:
	_bounce_vel = impulse

func stop_movement() -> void:
	_bounce_vel = Vector2.ZERO
	_wander_dir = Vector2.ZERO
	_wander_timer = _rng.randf_range(1.0, 2.0)

func feed() -> void:
	fish_fed += 1
	_chomp_timer = 0.3
	_feed_pop = 1.0

func promote() -> void:
	promoted = true
	_promote_timer = 0.6  # growth animation duration

func _draw() -> void:
	if promoted:
		_draw_adult()
	else:
		_draw_kid()

func _draw_adult() -> void:
	var off := _tremble
	# Adult seal — same style as seal.gd but drawn as Node2D
	var r := 28.0
	var center := Vector2(0, 0) + off
	# Body circle
	draw_circle(center, r, body_color)
	draw_arc(center, r, 0, TAU, 32, body_color.darkened(0.25), 2.0)
	# Belly highlight
	var belly_pts: PackedVector2Array = []
	for bi in range(16):
		var angle := TAU * bi / 16.0
		belly_pts.append(center + Vector2(cos(angle) * 16, sin(angle) * 12 + 4))
	draw_colored_polygon(belly_pts, body_color.lightened(0.2))
	# Eyes
	var look := sin(_look_phase * 1.5) * 2.0
	for side in [-1.0, 1.0]:
		var ep := center + Vector2(side * 8 + look, -8)
		draw_circle(ep, 5.5, Color(0.08, 0.06, 0.06))
		draw_circle(ep + Vector2(-1.0 * side, -1.2), 2.0, Color(1, 1, 1, 0.8))
	# Snout
	var sc := center + Vector2(look, 2)
	draw_circle(sc, 7.0, body_color.lightened(0.12))
	draw_circle(sc + Vector2(0, -1), 3.0, Color(0.2, 0.15, 0.15))
	for dx in [-5.0, -3.0, 3.0, 5.0]:
		draw_circle(sc + Vector2(dx, 3), 1.0, body_color.darkened(0.3))

func _draw_kid() -> void:
	var off := _tremble
	# Coat — lighter/warmer than parent
	var coat: Color = body_color.lightened(0.15)
	# Body — squat oval
	var bx := 22.0
	var by := 16.0
	var bc := Vector2(0, 4) + off
	_draw_oval(bc, bx, by, coat)
	_draw_oval_outline(bc, bx, by, coat.darkened(0.3), 1.5)
	# Flippers — small triangles on sides
	var fc := coat.darkened(0.1)
	draw_colored_polygon([bc + Vector2(-bx + 2, -4), bc + Vector2(-bx - 6, 2), bc + Vector2(-bx + 2, 6)], fc)
	draw_colored_polygon([bc + Vector2(bx - 2, -4), bc + Vector2(bx + 6, 2), bc + Vector2(bx - 2, 6)], fc)
	# Head
	var look := sin(_look_phase * 1.5) * 4.0
	var hc := Vector2(look, -10) + off
	draw_circle(hc, 12.0, coat.lightened(0.05))
	draw_arc(hc, 12.0, 0, TAU, 24, coat.darkened(0.25), 1.5)
	# Eyes — big and dark
	for side in [-1.0, 1.0]:
		var ep := hc + Vector2(side * 5.0, -2)
		draw_circle(ep, 3.5, Color(0.1, 0.08, 0.08))
		draw_circle(ep + Vector2(-0.8, -0.8), 1.2, Color(1, 1, 1, 0.7))
	# Snout + whiskers
	var sc := hc + Vector2(0, 4)
	draw_circle(sc, 5.0, coat.lightened(0.1))
	for dx in [-4.0, -2.0, 2.0, 4.0]:
		draw_circle(sc + Vector2(dx, 1.5), 0.8, coat.darkened(0.4))
	# Chomp mouth
	if _chomp_timer > 0.0:
		var open: float = sin(_chomp_timer / 0.3 * PI) * 3.0
		draw_line(sc + Vector2(-3, 3), sc + Vector2(0, 3 + open), coat.darkened(0.5), 1.5)
		draw_line(sc + Vector2(3, 3), sc + Vector2(0, 3 + open), coat.darkened(0.5), 1.5)

func _spawn_dive_ripple(arena: Node2D, pos: Vector2) -> void:
	## Lingering ripple at dive spot — visible for 5 seconds.
	var ripple := Node2D.new()
	ripple.global_position = pos
	ripple.z_index = -1
	ripple.set_script(preload("res://scripts/dive_ripple.gd"))
	arena.add_child(ripple)

func _draw_oval(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts: PackedVector2Array = []
	for i in range(24):
		var a := TAU * i / 24.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)

func _draw_oval_outline(center: Vector2, rx: float, ry: float, color: Color, width: float) -> void:
	var pts: PackedVector2Array = []
	for i in range(24):
		var a := TAU * i / 24.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	pts.append(pts[0])
	draw_polyline(pts, color, width)
