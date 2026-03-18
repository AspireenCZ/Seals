extends Node2D
## Main arena — ice floe, water zones, fish spawning, score tracking.
## Arena is procedurally generated each match.

const SealScene := preload("res://scripts/seal.gd")
const FishScript := preload("res://scripts/fish.gd")
const PenguinScript := preload("res://scripts/penguin.gd")
const BearScript := preload("res://scripts/bear.gd")
const SplashScript := preload("res://scripts/splash.gd")
const KidScript := preload("res://scripts/kid.gd")
const CadaverScript := preload("res://scripts/cadaver.gd")
const WalrusScript := preload("res://scripts/walrus.gd")
const OscillationGuard := preload("res://scripts/oscillation_guard.gd")

const SCORE_TO_WIN := 10
const VIEWPORT := Vector2(1920, 1080)
const ICE_CENTER := Vector2(960, 540)

## Generated per match
var ice_polygon: PackedVector2Array
var wall_edge_indices: Array[int]
var ice_holes: Array[PackedVector2Array]
var _respawn_points: Array[Vector2]
const HOME_RADIUS := 50.0
var _kids: Array[Node2D] = []
var _kid_start_positions: Array[Vector2] = []

## Players
var players: Array[CharacterBody2D] = []
var _penguins: Array[CharacterBody2D] = []
var _bears: Array[CharacterBody2D] = []
var _walruses: Array[CharacterBody2D] = []
var scores: Array[int] = [0, 0, 0, 0]  # ready for 4
var total_fish := 0

## Spawn
var _spawn_timer := 3.5
var _fish_on_field := 0
var _rng := RandomNumberGenerator.new()

## Animal pacing — gradual introduction
var _match_time := 0.0
var _next_penguin_time := 0.0
var _penguins_spawned := 0
var _max_penguins := 0
var _bear_spawned := false
var _bear_time := 0.0
var _walrus_spawned := false
var _walrus_time := 0.0

## Camera / isometric transform
var _drift_time := 0.0
const ISO_CANVAS_Y := 0.72                              ## Y compression for semi-iso perspective
const ISO_ORIGIN_Y := ICE_CENTER.y * (1.0 - 0.72)      ## ≈ 151 — re-centres after squish

## UI
var _canvas: CanvasLayer
var _progress_bars: Array[ColorRect] = []  # filled portion per player
var _progress_bgs: Array[ColorRect] = []   # background per player
var _winner_panel: Control
var _player_colors: Array[Color] = [Color(0.3, 0.55, 0.85), Color(0.85, 0.35, 0.3), Color(0.3, 0.75, 0.4), Color(0.8, 0.7, 0.2)]

## Nodes created per arena (cleared on regenerate)
var _arena_nodes: Array[Node] = []
var _wall_body: StaticBody2D

func _ready() -> void:
	_rng.randomize()
	_generate_arena()
	_build_arena()
	_spawn_players()
	_init_animal_pacing()
	_build_ui()
	_build_camera()
	_start_ambient()

func _start_ambient() -> void:
	var stream: AudioStreamMP3 = load("res://assets/Sounds/Ambient/ambient-sunnyday.mp3")
	if stream == null:
		push_warning("Ambient sound not found — check import.")
		return
	stream.loop = true
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -6.0
	add_child(player)
	player.play()

## ============================================================
## Arena generation
## ============================================================

func _generate_arena() -> void:
	_generate_ice_polygon()
	_generate_wall_edges()
	_generate_features()
	_generate_kids()
	_compute_respawn_points()

func _generate_ice_polygon() -> void:
	## Random irregular convex-ish ice floe.
	var num_verts := _rng.randi_range(10, 18)
	var base_radius_x := _rng.randf_range(690, 870)
	var base_radius_y := _rng.randf_range(405, 510)

	ice_polygon = PackedVector2Array()
	for i in range(num_verts):
		var angle := TAU * i / num_verts
		# Per-vertex radius jitter for irregular shape
		var jitter_x := _rng.randf_range(0.75, 1.15)
		var jitter_y := _rng.randf_range(0.75, 1.15)
		var rx := base_radius_x * jitter_x
		var ry := base_radius_y * jitter_y
		var pt := ICE_CENTER + Vector2(cos(angle) * rx, sin(angle) * ry)
		# Clamp to stay visible on screen with margin
		pt.x = clampf(pt.x, 150, 1770)
		pt.y = clampf(pt.y, 120, 990)
		ice_polygon.append(pt)

func _generate_wall_edges() -> void:
	## Randomly assign ~50-70% of edges as walls.
	wall_edge_indices = []
	var wall_ratio := _rng.randf_range(0.45, 0.7)
	var edge_count := ice_polygon.size()
	# Pick random edges, but ensure at least some open water
	var indices: Array[int] = []
	for i in range(edge_count):
		indices.append(i)
	indices.shuffle()
	var wall_count := int(edge_count * wall_ratio)
	wall_count = clampi(wall_count, 2, edge_count - 2)  # at least 2 walls, at least 2 open
	for i in range(wall_count):
		wall_edge_indices.append(indices[i])

func _generate_kids() -> void:
	## Place kids at opposite sides of the ice — leftmost and rightmost edge points.
	_kid_start_positions = []
	var left_pt := ice_polygon[0]
	var right_pt := ice_polygon[0]
	for pt in ice_polygon:
		if pt.x < left_pt.x:
			left_pt = pt
		if pt.x > right_pt.x:
			right_pt = pt
	var inward_left := (ICE_CENTER - left_pt).normalized() * 150
	var inward_right := (ICE_CENTER - right_pt).normalized() * 150
	_kid_start_positions.append(left_pt + inward_left)
	_kid_start_positions.append(right_pt + inward_right)

func _generate_features() -> void:
	## Randomly pick an arena theme:
	## 0 = empty, 1 = one hole, 2 = two holes, 3 = three holes
	ice_holes = []
	var theme := _rng.randi_range(0, 3)
	var hole_count := theme  # 0-3 holes
	for _i in range(hole_count):
		var hole := _make_hole()
		if hole.size() > 0:
			ice_holes.append(hole)

func _make_hole() -> PackedVector2Array:
	## Generate a water hole polygon inside the ice. Can be small or large.
	var radius := _rng.randf_range(45, 180)
	var min_edge_margin := radius + 60

	var center := Vector2.ZERO
	for _attempt in range(40):
		var candidate := ICE_CENTER + Vector2(_rng.randf_range(-375, 375), _rng.randf_range(-225, 225))
		if not _is_point_inside_polygon(candidate, ice_polygon):
			continue
		var min_edge_dist := _min_dist_to_polygon_edge(candidate, ice_polygon)
		if min_edge_dist < min_edge_margin:
			continue
		var overlaps := false
		for existing in ice_holes:
			var existing_center := _polygon_center(existing)
			if candidate.distance_to(existing_center) < radius + 80:
				overlaps = true
				break
		if overlaps:
			continue
		center = candidate
		break

	if center == Vector2.ZERO:
		return PackedVector2Array()

	var num_pts := _rng.randi_range(6, 10)
	var hole := PackedVector2Array()
	for i in range(num_pts):
		var angle := TAU * i / num_pts
		var r := radius * _rng.randf_range(0.7, 1.2)
		hole.append(center + Vector2(cos(angle) * r, sin(angle) * r * 0.8))
	return hole

func _compute_respawn_points() -> void:
	## Find 4 safe points well inside the ice, away from holes and obstacles.
	_respawn_points = []
	for _i in range(4):
		var best := ICE_CENTER
		for _attempt in range(40):
			var pt := ICE_CENTER + Vector2(_rng.randf_range(-300, 300), _rng.randf_range(-180, 180))
			if not _is_safe_spot(pt, 60):
				continue
			var ok := true
			for rp in _respawn_points:
				if pt.distance_to(rp) < 100:
					ok = false
					break
			if ok:
				best = pt
				break
		_respawn_points.append(best)

func _is_safe_spot(pt: Vector2, margin: float) -> bool:
	## Check point is on ice, away from edges, holes, and obstacles.
	if not _is_on_ice(pt):
		return false
	if _min_dist_to_polygon_edge(pt, ice_polygon) < margin:
		return false
	for hole in ice_holes:
		if pt.distance_to(_polygon_center(hole)) < 80:
			return false
	return true

## ============================================================
## Arena building (visuals + physics from generated data)
## ============================================================

func _build_arena() -> void:
	# Ocean background — deep gradient via stacked rects
	var bg_deep := ColorRect.new()
	bg_deep.color = Color(0.06, 0.14, 0.35)
	bg_deep.position = Vector2(-200, -200)
	bg_deep.size = VIEWPORT + Vector2(400, 400)
	bg_deep.z_index = -12
	_add_arena_node(bg_deep)

	# Mid-depth ocean layer
	var bg_mid := ColorRect.new()
	bg_mid.color = Color(0.1, 0.25, 0.52, 0.7)
	bg_mid.position = Vector2(-100, -100)
	bg_mid.size = VIEWPORT + Vector2(200, 200)
	bg_mid.z_index = -11
	_add_arena_node(bg_mid)

	# Lighter near-surface layer
	var bg_surf := ColorRect.new()
	bg_surf.color = Color(0.14, 0.32, 0.6, 0.5)
	bg_surf.position = Vector2(0, 0)
	bg_surf.size = VIEWPORT
	bg_surf.z_index = -10
	_add_arena_node(bg_surf)

	# Ocean wave lines
	var waves := Node2D.new()
	waves.z_index = -9
	waves.set_script(preload("res://scripts/waves.gd"))
	_add_arena_node(waves)

	# Ice floe polygon — base layer
	var ice := Polygon2D.new()
	ice.polygon = ice_polygon
	ice.color = Color(0.88, 0.92, 0.96)
	ice.z_index = -5
	_add_arena_node(ice)

	# Ice highlight — slightly smaller, brighter polygon for frosty center
	var shrunk: PackedVector2Array = []
	for pt in ice_polygon:
		shrunk.append(pt.lerp(ICE_CENTER, 0.15))
	var ice_hi := Polygon2D.new()
	ice_hi.polygon = shrunk
	ice_hi.color = Color(0.94, 0.97, 1.0, 0.5)
	ice_hi.z_index = -4
	_add_arena_node(ice_hi)

	# Ice edge glow — subtle blue-white rim around the floe
	var rim := Line2D.new()
	rim.points = ice_polygon
	rim.closed = true
	rim.width = 6.0
	rim.default_color = Color(0.6, 0.78, 0.95, 0.3)
	rim.z_index = -4
	_add_arena_node(rim)

	# Ice cliff faces — give the floe a 3D raised-platform look in iso view.
	# Each edge facing "downward" (toward viewer) gets a shaded quad below it.
	# CLIFF_DEPTH is in world-space px; canvas Y-squish makes it look ~30 screen-px deep.
	const CLIFF_DEPTH := 42.0
	for ci in range(ice_polygon.size()):
		var cni := (ci + 1) % ice_polygon.size()
		var ca: Vector2 = ice_polygon[ci]
		var cb: Vector2 = ice_polygon[cni]
		var cmid := (ca + cb) * 0.5
		var cout := (cmid - ICE_CENTER).normalized()
		if cout.y < -0.5:  # edge faces nearly straight up — not visible as a cliff
			continue
		# Fake lighting: edges facing right are slightly darker
		var shade := remap(cout.x, -1.0, 1.0, 0.92, 0.60)
		var cliff_c := Color(0.58 * shade, 0.74 * shade, 0.90 * shade)
		var cliff_quad := Polygon2D.new()
		cliff_quad.polygon = PackedVector2Array([
			ca, cb,
			cb + Vector2(0.0, CLIFF_DEPTH),
			ca + Vector2(0.0, CLIFF_DEPTH)
		])
		cliff_quad.color = cliff_c
		cliff_quad.z_index = -6  # behind ice surface, above ocean
		_add_arena_node(cliff_quad)
		# Bottom shadow line
		var cliff_edge := Line2D.new()
		cliff_edge.points = PackedVector2Array([
			ca + Vector2(0.0, CLIFF_DEPTH),
			cb + Vector2(0.0, CLIFF_DEPTH)
		])
		cliff_edge.width = 2.5
		cliff_edge.default_color = Color(0.25, 0.38, 0.55, 0.5)
		cliff_edge.z_index = -6
		_add_arena_node(cliff_edge)

	# Edge drawing — walls vs open water
	for idx in range(ice_polygon.size()):
		var next_idx := (idx + 1) % ice_polygon.size()
		var a: Vector2 = ice_polygon[idx]
		var b: Vector2 = ice_polygon[next_idx]
		var is_wall := idx in wall_edge_indices

		if is_wall:
			var mid := (a + b) * 0.5
			var inward := (ICE_CENTER - mid).normalized()
			var outward := -inward
			# Mantinel — thick hockey board, dark wood tones
			var base := Line2D.new()
			base.points = [a + outward * 4, b + outward * 4]
			base.width = 20.0
			base.default_color = Color(0.15, 0.12, 0.1)
			base.z_index = -3
			_add_arena_node(base)
			var board := Line2D.new()
			board.points = [a, b]
			board.width = 16.0
			board.default_color = Color(0.45, 0.32, 0.2)
			board.z_index = -2
			_add_arena_node(board)
			var top_edge := Line2D.new()
			top_edge.points = [a + inward * 2, b + inward * 2]
			top_edge.width = 3.0
			top_edge.default_color = Color(0.6, 0.45, 0.3)
			top_edge.z_index = -1
			_add_arena_node(top_edge)
			var bottom_edge := Line2D.new()
			bottom_edge.points = [a + outward * 6, b + outward * 6]
			bottom_edge.width = 2.0
			bottom_edge.default_color = Color(0.25, 0.18, 0.12)
			bottom_edge.z_index = -1
			_add_arena_node(bottom_edge)
		else:
			var edge_line := Line2D.new()
			edge_line.points = [a, b]
			edge_line.width = 2.0
			edge_line.default_color = Color(0.2, 0.4, 0.7, 0.7)
			edge_line.z_index = -4
			_add_arena_node(edge_line)

	# Ice surface cracks — branching
	var cracks := Node2D.new()
	cracks.z_index = -3
	var crack_count := _rng.randi_range(6, 14)
	for _i in range(crack_count):
		var start := _random_point_on_ice()
		var dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		var seg_count := _rng.randi_range(2, 5)
		var pts: PackedVector2Array = [start]
		var pos := start
		for _s in range(seg_count):
			dir = dir.rotated(_rng.randf_range(-0.6, 0.6))
			pos += dir * _rng.randf_range(20, 60)
			pts.append(pos)
		var line := Line2D.new()
		line.points = pts
		line.width = _rng.randf_range(0.5, 1.5)
		line.default_color = Color(0.7, 0.82, 0.92, _rng.randf_range(0.2, 0.5))
		cracks.add_child(line)
		# Branch from midpoint
		if seg_count > 2 and _rng.randf() < 0.5:
			var branch_start: Vector2 = pts[1]
			var branch_dir := dir.rotated(_rng.randf_range(0.5, 1.2) * (1 if _rng.randf() > 0.5 else -1))
			var branch := Line2D.new()
			branch.points = [branch_start, branch_start + branch_dir * _rng.randf_range(15, 40)]
			branch.width = 0.8
			branch.default_color = Color(0.72, 0.84, 0.94, 0.3)
			cracks.add_child(branch)
	_add_arena_node(cracks)

	# Snow patches — scattered bright spots on ice
	var snow := Node2D.new()
	snow.z_index = -3
	for _i in range(_rng.randi_range(8, 16)):
		var pt := _random_point_on_ice()
		var sz := _rng.randf_range(8, 25)
		var patch_pts: PackedVector2Array = []
		var num := _rng.randi_range(6, 10)
		for pi in range(num):
			var angle := TAU * pi / num
			var r := sz * _rng.randf_range(0.6, 1.2)
			patch_pts.append(pt + Vector2(cos(angle) * r, sin(angle) * r * 0.7))
		var patch := Polygon2D.new()
		patch.polygon = patch_pts
		patch.color = Color(0.96, 0.98, 1.0, _rng.randf_range(0.15, 0.35))
		snow.add_child(patch)
	_add_arena_node(snow)

	# Holes — deep water with layered visuals
	for hole in ice_holes:
		# Deep water fill
		var h := Polygon2D.new()
		h.polygon = hole
		h.color = Color(0.06, 0.18, 0.42, 0.9)
		h.z_index = -3
		_add_arena_node(h)
		# Lighter inner water
		var hole_center := _polygon_center(hole)
		var inner_hole: PackedVector2Array = []
		for pt in hole:
			inner_hole.append(pt.lerp(hole_center, 0.3))
		var hi := Polygon2D.new()
		hi.polygon = inner_hole
		hi.color = Color(0.1, 0.28, 0.55, 0.6)
		hi.z_index = -2
		_add_arena_node(hi)
		# Ice rim around hole
		var rim_outer := Line2D.new()
		rim_outer.points = hole
		rim_outer.closed = true
		rim_outer.width = 5.0
		rim_outer.default_color = Color(0.75, 0.85, 0.95, 0.6)
		rim_outer.z_index = -2
		_add_arena_node(rim_outer)
		var rim_inner := Line2D.new()
		var rim_pts: PackedVector2Array = []
		for pt in hole:
			rim_pts.append(pt.lerp(hole_center, 0.08))
		rim_inner.points = rim_pts
		rim_inner.closed = true
		rim_inner.width = 2.0
		rim_inner.default_color = Color(0.5, 0.68, 0.88, 0.4)
		rim_inner.z_index = -1
		_add_arena_node(rim_inner)

	# Baby seals
	_kids.clear()
	for i in range(mini(_kid_start_positions.size(), 2)):
		var kid := Node2D.new()
		kid.set_script(KidScript)
		kid.player_index = i
		kid.body_color = _player_colors[i]
		kid.position = _kid_start_positions[i]
		kid.add_child(OscillationGuard.new())
		_add_arena_node(kid)
		_kids.append(kid)

	# Wall collision body
	_wall_body = StaticBody2D.new()
	_wall_body.collision_layer = 1
	_wall_body.collision_mask = 0
	var wall_vertices_used := {}  # smooth corners at junctions
	for idx in wall_edge_indices:
		var next_idx := (idx + 1) % ice_polygon.size()
		var seg := CollisionShape2D.new()
		var shape := SegmentShape2D.new()
		shape.a = ice_polygon[idx]
		shape.b = ice_polygon[next_idx]
		seg.shape = shape
		_wall_body.add_child(seg)
		# Add circle caps at vertices to prevent wedging at segment junctions
		for vi in [idx, next_idx]:
			if vi not in wall_vertices_used:
				wall_vertices_used[vi] = true
				var cap := CollisionShape2D.new()
				var circle := CircleShape2D.new()
				circle.radius = 4.0
				cap.shape = circle
				cap.position = ice_polygon[vi]
				_wall_body.add_child(cap)
	_add_arena_node(_wall_body)

func _add_arena_node(node: Node) -> void:
	add_child(node)
	_arena_nodes.append(node)

func _clear_arena() -> void:
	for node in _arena_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_arena_nodes.clear()
	_kids.clear()
	_wall_body = null

## ============================================================
## Physics
## ============================================================

func _physics_process(_delta: float) -> void:
	# Kid feeding check — skip if kid is hiding in water
	for p in players:
		if p._has_fish and not p._is_in_water:
			if p.player_index < _kids.size() and not _kids[p.player_index].in_water:
				var kid_pos: Vector2 = _kids[p.player_index].position
				if p.global_position.distance_to(kid_pos) < HOME_RADIUS:
					p.deliver_fish()

	# Seal bumps kid — own kid with fish skipped (delivery handles it), otherwise bounce
	for p in players:
		if not p._is_in_water:
			for kid in _kids:
				if kid.in_water:
					continue
				var dist: float = p.global_position.distance_to(kid.position)
				if dist < 45.0 and dist > 0.1:
					# Own kid + carrying fish → skip (delivery proximity handles it)
					if kid.player_index == p.player_index and p._has_fish:
						continue
					var away: Vector2 = (kid.position - p.global_position).normalized()
					var force: float = clampf(p.velocity.length() * 0.6, 100.0, 350.0)
					kid.bounce(away * force)

	for p in players:
		if p.has_method("fall_in_water") and not p._is_in_water:
			if not _is_on_ice(p.global_position):
				p.fall_in_water()
	# Penguin water check
	for pg in _penguins:
		if not is_instance_valid(pg):
			continue
		if pg.state == pg.State.ACTIVE:
			# Active: fall off edges only — penguins cross holes freely when chasing fish
			if not _is_on_ice(pg.global_position):
				var in_hole := false
				for hole in ice_holes:
					if Geometry2D.is_point_in_polygon(pg.global_position, hole):
						in_hole = true
						break
				if not in_hole:
					pg.fall_in_water("edge")
		elif pg.state == pg.State.LEAVING:
			# Leaving (has fish): holes trap them — sink and drop fish
			for hole in ice_holes:
				if Geometry2D.is_point_in_polygon(pg.global_position, hole):
					pg.fall_in_water("hole")
					break
	# Walrus boundary — bounced off ice = destroyed
	for walrus in _walruses:
		if is_instance_valid(walrus) and walrus.state == walrus.State.ACTIVE:
			if not _is_on_ice(walrus.global_position):
				_spawn_splash(walrus.global_position, 4)  # BEAR_IN splash
				walrus.queue_free()
	# Bear boundary check — snap back onto ice, never flicker
	for bear in _bears:
		if is_instance_valid(bear) and bear.state == bear.State.ACTIVE:
			if not _is_on_ice(bear.global_position):
				bear.global_position = _snap_to_ice(bear.global_position)
				bear.velocity = Vector2.ZERO
	# Bear eats kid — contact range, -5 score, kid respawns in 5s
	for bear in _bears:
		if is_instance_valid(bear) and bear.state == bear.State.ACTIVE:
			for kid in _kids:
				if kid.in_water:
					continue
				if bear.global_position.distance_to(kid.position) < 55.0:
					var pi: int = kid.player_index
					scores[pi] = maxi(scores[pi] - 5, 0)
					_update_ui()
					_spawn_float_text(pi, "-5")
					_spawn_cadaver(kid.position)
					kid._dive(self)
					kid._water_timer = 5.0

## ============================================================
## Players
## ============================================================

func _spawn_players() -> void:
	var colors: Array[Color] = [Color(0.3, 0.55, 0.85), Color(0.85, 0.35, 0.3), Color(0.3, 0.75, 0.4), Color(0.8, 0.7, 0.2)]
	var num_players := 2  # Change to 4 later

	for i in range(num_players):
		var w := CharacterBody2D.new()
		w.set_script(SealScene)
		w.player_index = i
		w.body_color = colors[i]
		w.collision_layer = 2
		w.collision_mask = 1 | 2
		w.position = _pick_water_respawn()

		var col := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 28.0
		col.shape = circle
		w.add_child(col)

		w.fish_delivered.connect(_on_fish_delivered)
		w.fish_dropped_by_player.connect(_on_player_dropped_fish)
		w.fell_in_water.connect(_on_fell_in_water)
		w.killed_by_enemy.connect(_on_killed_by_enemy)
		w.add_child(OscillationGuard.new())
		add_child(w)
		players.append(w)

func _init_animal_pacing() -> void:
	_match_time = 0.0
	_penguins_spawned = 0
	_bear_spawned = false
	_walrus_spawned = false
	_max_penguins = _rng.randi_range(2, 3)
	_next_penguin_time = _rng.randf_range(6.0, 10.0)
	_bear_time = _rng.randf_range(35.0, 50.0)
	_walrus_time = _rng.randf_range(20.0, 30.0)

func _update_animal_pacing(delta: float) -> void:
	_match_time += delta
	# Penguin ramp — one at a time with increasing intervals
	if _penguins_spawned < _max_penguins and _match_time >= _next_penguin_time:
		_spawn_one_penguin()
		_penguins_spawned += 1
		# Next penguin comes later
		_next_penguin_time = _match_time + _rng.randf_range(10.0, 18.0)
	# Bear — arrives late as the big threat (disabled for now)
	#if not _bear_spawned and _match_time >= _bear_time:
	#	_bear_spawned = true
	#	_spawn_bear()
	# Walrus — mid-game aggressive enemy
	if not _walrus_spawned and _match_time >= _walrus_time:
		_walrus_spawned = true
		_spawn_walrus()

func _spawn_one_penguin() -> void:
	var p := CharacterBody2D.new()
	p.set_script(PenguinScript)
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	col.shape = circle
	p.add_child(col)
	p.fish_stolen.connect(_on_fish_stolen)
	p.fish_dropped.connect(_on_fish_dropped)
	p.add_child(OscillationGuard.new())
	add_child(p)
	_penguins.append(p)

func _spawn_bear() -> void:
	var b := CharacterBody2D.new()
	b.set_script(BearScript)
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 50.0
	col.shape = circle
	b.add_child(col)
	b.fish_stolen.connect(_on_fish_stolen)
	b.add_child(OscillationGuard.new())
	add_child(b)
	_bears.append(b)

func _spawn_walrus() -> void:
	var w := CharacterBody2D.new()
	w.set_script(WalrusScript)
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	col.shape = circle
	w.add_child(col)
	w.fish_stolen.connect(_on_fish_stolen)
	w.add_child(OscillationGuard.new())
	add_child(w)
	_walruses.append(w)

func _on_fish_stolen() -> void:
	# Enemy escaped with a fish — gone for good
	total_fish += 1
	_update_ui()

func _on_fish_delivered(player_index: int, origin: String) -> void:
	if player_index < _kids.size():
		_kids[player_index].feed()
	scores[player_index] += 1
	_update_ui()
	_score_pop(player_index, 1)

func _on_fish_dropped(pos: Vector2) -> void:
	pass  # penguin drop — no announcement (only on delivery)

func _on_player_dropped_fish(pos: Vector2, _player_index: int) -> void:
	# Seal dropped fish — spawn directly on ice, never near the seal's body.
	# Root cause fix: starting the jump near the seal creates a physics overlap
	# that fires body_entered before Godot syncs the seal's new position.
	var landing := pos + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30))
	if not _is_on_ice(landing):
		landing = _find_nearest_ice_point(pos)
	var fish := Area2D.new()
	fish.set_script(FishScript)
	fish.origin = "opponent"
	fish.tree_exiting.connect(func(): _fish_on_field -= 1)
	add_child(fish)
	# Pop in place at the landing position — no travel from seal's position
	fish.start_jump(landing, landing, 0.3, 30.0)
	_fish_on_field += 1

func _find_nearest_ice_point(from: Vector2) -> Vector2:
	return _snap_to_ice(from)

## ============================================================
## UI
func _snap_to_ice(from: Vector2) -> Vector2:
	## Find nearest on-ice point by radial sampling. Guaranteed no flicker.
	var best: Vector2 = ICE_CENTER
	var best_dist := from.distance_to(ICE_CENTER)
	# Sample in expanding rings around the off-ice position
	for radius in [10.0, 25.0, 50.0, 80.0, 120.0]:
		for step in range(16):
			var angle := TAU * step / 16.0
			var candidate: Vector2 = from + Vector2(cos(angle), sin(angle)) * radius
			if _is_on_ice(candidate):
				var d := from.distance_to(candidate)
				if d < best_dist:
					best_dist = d
					best = candidate
		if best_dist < 900.0:  # found something closer than center
			return best
	return best

## ============================================================

const BAR_WIDTH := 28.0
const BAR_HEIGHT := 600.0
const BAR_MARGIN := 20.0
const BAR_Y := 240.0  # vertically centered-ish

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	_progress_bars = []
	_progress_bgs = []

	# P1 bar on left edge, P2 bar on right edge
	var bar_positions := [
		Vector2(BAR_MARGIN, BAR_Y),                          # P1 left
		Vector2(1920.0 - BAR_MARGIN - BAR_WIDTH, BAR_Y),    # P2 right
	]

	for i in range(2):
		# Background (dark, full height)
		var bg := ColorRect.new()
		bg.position = bar_positions[i]
		bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		bg.color = Color(0.1, 0.1, 0.15, 0.6)
		_canvas.add_child(bg)
		_progress_bgs.append(bg)

		# Border
		var border := ReferenceRect.new()
		border.position = bar_positions[i]
		border.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		border.border_color = Color(_player_colors[i], 0.5)
		border.border_width = 2.0
		border.editor_only = false
		_canvas.add_child(border)

		# Fill (grows from bottom)
		var fill := ColorRect.new()
		fill.position = Vector2(bar_positions[i].x, bar_positions[i].y + BAR_HEIGHT)
		fill.size = Vector2(BAR_WIDTH, 0)
		fill.color = Color(_player_colors[i], 0.85)
		_canvas.add_child(fill)
		_progress_bars.append(fill)

	# --- Winner overlay (hidden until game over) ---
	_winner_panel = Control.new()
	_winner_panel.visible = false
	_winner_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_winner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dim overlay
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_winner_panel.add_child(dim)

	# Glow bar behind text (winner's color, set at game over)
	var glow := ColorRect.new()
	glow.name = "Glow"
	glow.position = Vector2(0, 380)
	glow.size = Vector2(1920, 320)
	glow.color = Color(1, 1, 1, 0.15)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_winner_panel.add_child(glow)

	# Winner text
	var wl := Label.new()
	wl.name = "WinnerLabel"
	wl.position = Vector2(0, 400)
	wl.size = Vector2(1920, 120)
	wl.add_theme_font_size_override("font_size", 96)
	wl.add_theme_color_override("font_color", Color.WHITE)
	wl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	wl.add_theme_constant_override("outline_size", 8)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_winner_panel.add_child(wl)

	# Restart prompt (pulsing)
	var rl := Label.new()
	rl.name = "RestartLabel"
	rl.position = Vector2(0, 540)
	rl.size = Vector2(1920, 60)
	rl.text = "SPACE to play again"
	rl.add_theme_font_size_override("font_size", 28)
	rl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.7))
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner_panel.add_child(rl)

	_canvas.add_child(_winner_panel)

	_update_ui()

func _build_camera() -> void:
	## iso3d: no Camera2D — canvas_transform is managed directly in _process.
	_apply_iso_transform(Vector2.ZERO)

func _apply_iso_transform(drift: Vector2) -> void:
	## Squish Y by ISO_CANVAS_Y so the flat top-down world looks semi-isometric.
	## CanvasLayer (UI) is on a separate canvas and is unaffected.
	get_viewport().canvas_transform = Transform2D(
		Vector2(1.0, 0.0),
		Vector2(0.0, ISO_CANVAS_Y),
		Vector2(-drift.x, ISO_ORIGIN_Y - drift.y * ISO_CANVAS_Y)
	)

## ============================================================
## Game loop
## ============================================================

func _process(delta: float) -> void:
	if _check_winner() >= 0:
		_handle_game_over()
		return

	_drift_time += delta
	_apply_iso_transform(Vector2(sin(_drift_time * 0.3) * 8.0, cos(_drift_time * 0.2) * 5.0))

	_update_animal_pacing(delta)

	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _fish_on_field < 2:
		_spawn_fish()
		# Longer gaps — sometimes no fish for a while
		_spawn_timer = _rng.randf_range(3.0, 7.0)

func _spawn_fish() -> void:
	if _check_winner() >= 0 or _fish_on_field >= 3:
		return
	var landing := _pick_spawn_location()
	var source := _pick_jump_source(landing)
	var fish := Area2D.new()
	fish.set_script(FishScript)
	fish.tree_exiting.connect(func(): _fish_on_field -= 1)
	add_child(fish)
	fish.start_jump(source, landing)
	_fish_on_field += 1

func _pick_spawn_location() -> Vector2:
	var strategy := _rng.randf()
	if strategy < 0.4 and players.size() >= 2:
		var mid := (players[0].global_position + players[1].global_position) * 0.5
		mid += Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-60, 60))
		if _is_on_ice(mid):
			return mid
	if strategy < 0.7 and players.size() >= 2:
		var mid := ICE_CENTER + Vector2(_rng.randf_range(-120, 120), _rng.randf_range(-80, 80))
		if _is_on_ice(mid):
			var ok := true
			for p in players:
				if mid.distance_to(p.global_position) < 80:
					ok = false
					break
			if ok:
				return mid
	for _attempt in range(20):
		var pt := _random_point_on_ice()
		var too_close := false
		for p in players:
			if pt.distance_to(p.global_position) < 60:
				too_close = true
				break
		if not too_close:
			return pt
	return _random_point_on_ice()

func _pick_jump_source(landing: Vector2) -> Vector2:
	if _rng.randf() < 0.3 and ice_holes.size() > 0:
		var hole: PackedVector2Array = ice_holes[_rng.randi() % ice_holes.size()]
		return _polygon_center(hole)
	var nearest_edge_pt := ice_polygon[0]
	var min_dist := landing.distance_to(ice_polygon[0])
	for pt in ice_polygon:
		var d := landing.distance_to(pt)
		if d < min_dist:
			min_dist = d
			nearest_edge_pt = pt
	var outward := (nearest_edge_pt - ICE_CENTER).normalized()
	return nearest_edge_pt + outward * _rng.randf_range(40, 100)

## ============================================================
## Geometry helpers
## ============================================================

func _is_on_ice(point: Vector2) -> bool:
	if not _is_point_inside_polygon(point, ice_polygon):
		return false
	for hole in ice_holes:
		if _is_point_inside_polygon(point, hole):
			return false
	return true

func _is_point_inside_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)

func _random_point_on_ice() -> Vector2:
	for _i in range(50):
		var pt := Vector2(
			_rng.randf_range(180, 1740),
			_rng.randf_range(150, 960)
		)
		if _is_on_ice(pt):
			return pt
	return ICE_CENTER

func get_open_water_point() -> Dictionary:
	## Returns {edge_mid: Vector2, ocean: Vector2} for a random open (non-wall) edge.
	## edge_mid is on the ice boundary, ocean is offset outward into the water.
	var open_edges: Array[int] = []
	for idx in range(ice_polygon.size()):
		if idx not in wall_edge_indices:
			open_edges.append(idx)
	if open_edges.is_empty():
		# Fallback: use any edge
		open_edges.append(0)
	var idx: int = open_edges[_rng.randi() % open_edges.size()]
	var next_idx := (idx + 1) % ice_polygon.size()
	var a: Vector2 = ice_polygon[idx]
	var b: Vector2 = ice_polygon[next_idx]
	var mid := a.lerp(b, _rng.randf_range(0.2, 0.8))
	var outward := (mid - ICE_CENTER).normalized()
	var ocean := mid + outward * _rng.randf_range(80, 160)
	return {edge_mid = mid, ocean = ocean}

func _polygon_center(poly: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for pt in poly:
		center += pt
	return center / poly.size()

func _min_dist_to_polygon_edge(point: Vector2, polygon: PackedVector2Array) -> float:
	return point.distance_to(_nearest_polygon_edge_point(point, polygon))

func _nearest_polygon_edge_point(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	var best := polygon[0]
	var min_d := INF
	for i in range(polygon.size()):
		var j := (i + 1) % polygon.size()
		var closest := Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[j])
		var d := point.distance_to(closest)
		if d < min_d:
			min_d = d
			best = closest
	return best

## ============================================================
## Scoring & game state
## ============================================================

func _on_fell_in_water(player_index: int) -> void:
	# Splash effect at seal position
	if player_index < players.size():
		_spawn_splash(players[player_index].global_position, SplashScript.Kind.SEAL_IN)

func _on_killed_by_enemy(player_index: int) -> void:
	scores[player_index] = maxi(scores[player_index] - 1, 0)
	_update_ui()
	_spawn_float_text(player_index, "-1")

func _spawn_cadaver(pos: Vector2) -> void:
	var cadaver := Node2D.new()
	cadaver.set_script(CadaverScript)
	cadaver.global_position = pos
	add_child(cadaver)

func _spawn_splash(pos: Vector2, kind: int) -> void:
	var splash := Node2D.new()
	splash.set_script(SplashScript)
	splash.kind = kind
	splash.global_position = pos
	add_child(splash)

func _update_ui() -> void:
	for i in range(mini(players.size(), _progress_bars.size())):
		var fill: float = clampf(float(scores[i]) / SCORE_TO_WIN, 0.0, 1.0)
		var fill_height: float = BAR_HEIGHT * fill
		var bar: ColorRect = _progress_bars[i]
		var bg: ColorRect = _progress_bgs[i]
		# Bar grows from bottom: position moves up, size grows down
		bar.position.y = bg.position.y + BAR_HEIGHT - fill_height
		bar.size.y = fill_height

func _score_pop(player_index: int, points: int = 1) -> void:
	if player_index >= _progress_bars.size():
		return
	var bar: ColorRect = _progress_bars[player_index]
	var tw := create_tween()
	tw.tween_property(bar, "scale:x", 1.5, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(bar, "scale:x", 1.0, 0.2).set_ease(Tween.EASE_IN)
	_spawn_float_text(player_index, "+%d" % points)

func _spawn_float_text(player_index: int, text: String) -> void:
	var player: CharacterBody2D = players[player_index]
	var float_label := Label.new()
	float_label.text = text
	float_label.add_theme_font_size_override("font_size", 32)
	float_label.add_theme_color_override("font_color", _player_colors[player_index])
	float_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	float_label.add_theme_constant_override("outline_size", 3)
	float_label.z_index = 20
	float_label.global_position = player.global_position + Vector2(-12, -40)
	add_child(float_label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(float_label, "position:y", float_label.position.y - 50, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(float_label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.set_parallel(false)
	tw.tween_callback(float_label.queue_free)

func _check_winner() -> int:
	## Returns player index of winner, or -1 if no winner yet.
	for i in range(players.size()):
		if scores[i] >= SCORE_TO_WIN:
			return i
	return -1

var _game_over_animated := false

func _handle_game_over() -> void:
	if not _game_over_animated:
		_game_over_animated = true
		_animate_victory()

	if Input.is_action_just_pressed("ui_accept"):
		_restart()

func _animate_victory() -> void:
	var winner := _check_winner()
	var color: Color = _player_colors[winner]
	var names := ["PLAYER 1", "PLAYER 2", "PLAYER 3", "PLAYER 4"]

	# Promote winner's kid to adult before showing win screen
	if winner < _kids.size() and not _kids[winner].in_water:
		_kids[winner].promote()

	_winner_panel.visible = true
	_winner_panel.modulate.a = 0.0

	# Set winner text
	var wl: Label = _winner_panel.get_node("WinnerLabel")
	wl.text = "%s WINS!" % names[winner]
	wl.add_theme_color_override("font_color", Color(color, 1.0))
	wl.scale = Vector2(0.3, 0.3)
	wl.pivot_offset = Vector2(960, 60)

	# Set glow to winner's color
	var glow: ColorRect = _winner_panel.get_node("Glow")
	glow.color = Color(color, 0.2)

	# Fade in overlay
	var tw := create_tween()
	tw.tween_property(_winner_panel, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)

	# Title slam — scale up then settle
	var tw2 := create_tween()
	tw2.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw2.tween_property(wl, "scale", Vector2(1.15, 1.15), 0.5)
	tw2.tween_property(wl, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_IN_OUT)

	# Glow pulse loop
	var tw3 := create_tween().set_loops()
	tw3.tween_property(glow, "color:a", 0.3, 0.8).set_ease(Tween.EASE_IN_OUT)
	tw3.tween_property(glow, "color:a", 0.1, 0.8).set_ease(Tween.EASE_IN_OUT)

	# Restart label pulse
	var rl: Label = _winner_panel.get_node("RestartLabel")
	var tw4 := create_tween().set_loops()
	tw4.tween_property(rl, "modulate:a", 1.0, 0.6)
	tw4.tween_property(rl, "modulate:a", 0.3, 0.6)

	# Flash the winning progress bar
	if winner < _progress_bars.size():
		var bar: ColorRect = _progress_bars[winner]
		var tw5 := create_tween().set_loops(5)
		tw5.tween_property(bar, "color", Color.WHITE, 0.1)
		tw5.tween_property(bar, "color", Color(color, 0.85), 0.2)

func _restart() -> void:
	scores = [0, 0, 0, 0]
	total_fish = 0
	_fish_on_field = 0
	_game_over_animated = false
	_winner_panel.visible = false

	# Reset promoted kids
	for kid in _kids:
		if is_instance_valid(kid):
			kid.promoted = false
			kid.queue_redraw()

	# Remove all fish
	for child in get_children():
		if child.has_method("start_jump"):
			child.queue_free()

	# Regenerate arena
	_clear_arena()
	_generate_arena()
	# Wait a frame for queue_free to complete, then rebuild
	await get_tree().process_frame
	_build_arena()

	# Reset players near their homes
	for i in range(players.size()):
		players[i].global_position = _kids[i].position if i < _kids.size() else _respawn_points[i]
		players[i].velocity = Vector2.ZERO
		players[i].visible = true
		players[i]._is_in_water = false
		players[i]._has_fish = false
		players[i]._fish_count = 0
		players[i]._fish_origins.clear()
		players[i].queue_redraw()

	# Remove old penguins and bears — pacing will respawn them
	for pg in _penguins:
		if is_instance_valid(pg):
			pg.queue_free()
	_penguins.clear()
	for bear in _bears:
		if is_instance_valid(bear):
			bear.queue_free()
	_bears.clear()
	for w in _walruses:
		if is_instance_valid(w):
			w.queue_free()
	_walruses.clear()

	_spawn_timer = 3.0
	_init_animal_pacing()
	_update_ui()

func get_respawn_position(_player_index: int) -> Vector2:
	## Water-adjacent respawn — emerge from open water or hole, away from enemies.
	var best_pos := _respawn_points[0]
	var best_score := -1.0
	for _attempt in range(12):
		var candidate := _pick_water_respawn()
		var min_dist := INF
		for bear in _bears:
			if is_instance_valid(bear):
				min_dist = minf(min_dist, bear.global_position.distance_to(candidate))
		if min_dist > best_score:
			best_score = min_dist
			best_pos = candidate
	return best_pos

func _pick_water_respawn() -> Vector2:
	## Point on ice near open water edge or ice hole — never near mantinels.
	var open_edges: Array[int] = []
	for idx in range(ice_polygon.size()):
		if idx not in wall_edge_indices:
			open_edges.append(idx)
	# Try ice hole (40% when holes exist)
	if ice_holes.size() > 0 and (open_edges.is_empty() or _rng.randf() < 0.4):
		for _attempt in range(6):
			var hole: PackedVector2Array = ice_holes[_rng.randi() % ice_holes.size()]
			var hc := _polygon_center(hole)
			var angle := _rng.randf() * TAU
			var target := hc + Vector2(cos(angle), sin(angle)) * _rng.randf_range(50, 70)
			if _is_on_ice(target):
				return target
	# Try open water edge (non-mantinel boundary)
	if not open_edges.is_empty():
		for _attempt in range(8):
			var idx: int = open_edges[_rng.randi() % open_edges.size()]
			var next_idx := (idx + 1) % ice_polygon.size()
			var edge_pt: Vector2 = ice_polygon[idx].lerp(ice_polygon[next_idx], _rng.randf_range(0.2, 0.8))
			var inward := (ICE_CENTER - edge_pt).normalized()
			var target := edge_pt + inward * _rng.randf_range(40, 70)
			if _is_on_ice(target):
				return target
		# Last resort: midpoint of a random open edge, pushed inward
		var idx: int = open_edges[_rng.randi() % open_edges.size()]
		var next_idx := (idx + 1) % ice_polygon.size()
		var mid: Vector2 = ice_polygon[idx].lerp(ice_polygon[next_idx], 0.5)
		return mid + (ICE_CENTER - mid).normalized() * 60.0
	return _random_point_on_ice()

func _unhandled_input(event: InputEvent) -> void:
	if _check_winner() >= 0 and event.is_action_pressed("ui_accept"):
		_restart()
