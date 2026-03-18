extends CharacterBody2D
## Seal player — hockey-puck on ice.
## Extend to 4 players by adding p3/p4 input actions + spawning more instances.

@export var player_index: int = 0  ## 0-based. Controls which input actions to read.
@export var body_color: Color = Color.CORNFLOWER_BLUE

## --- Tuning (ice feel) ---
const ACCEL := 600.0        ## pixels/s² — slow buildup
const MAX_SPEED := 420.0     ## unused, no cap
const BRAKE_ACCEL := 900.0   ## pixels/s² — braking is faster than accelerating
const BUMP_FORCE := 400.0    ## impulse on collision with another seal
const RADIUS := 28.0
const ISO_H := 20.0   ## body cylinder height in world-px (≈14 screen-px at canvas 0.72)

var _input_prefix: String
var _respawn_timer := 0.0
var _is_in_water := false
var _flash_timer := 0.0
var _bump_cooldown := 0.0
var _bounce_stun := 0.0  ## input suppressed after wall/player bounce
var _has_fish := false      ## true if carrying at least one fish
var _fish_count := 0        ## 0, 1, or 2
var _fish_origins: Array[String] = []  ## stack of origins, max 2
const MAX_FISH := 2
var _last_ice_pos := Vector2.ZERO  ## last known on-ice position for fish drops

signal fish_delivered(player_index: int, origin: String)
signal fish_dropped_by_player(pos: Vector2, player_index: int)
signal fell_in_water(player_index: int)
signal killed_by_enemy(player_index: int)

func _ready() -> void:
	_input_prefix = "p%d_" % (player_index + 1)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	queue_redraw()

func _draw() -> void:
	# --- ISO 3D: shadow + cylinder side (drawn behind body) ---
	# Drop shadow (flat ellipse on the "ground" below the creature)
	var shd_pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * i / 20.0
		shd_pts.append(Vector2(5.0 + cos(a) * (RADIUS + 3), RADIUS + ISO_H + 7.0 + sin(a) * 9.0))
	draw_colored_polygon(shd_pts, Color(0.0, 0.04, 0.10, 0.22))
	# Cylinder side (front face between top-face edge and ground level)
	var seg := 20
	var side_pts := PackedVector2Array()
	for i in range(seg + 1):
		var a := PI * i / seg
		side_pts.append(Vector2(cos(a) * RADIUS, sin(a) * RADIUS))
	for i in range(seg + 1):
		var a := PI * (seg - i) / seg
		side_pts.append(Vector2(cos(a) * RADIUS, sin(a) * RADIUS + ISO_H))
	draw_colored_polygon(side_pts, body_color.darkened(0.38))

	# Body
	draw_circle(Vector2.ZERO, RADIUS, body_color)
	# Outline
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, body_color.darkened(0.25), 2.0)
	# Belly highlight — lighter oval on front
	var belly_pts: PackedVector2Array = []
	for bi in range(16):
		var angle := TAU * bi / 16.0
		belly_pts.append(Vector2(cos(angle) * 16, sin(angle) * 12 + 4))
	draw_colored_polygon(belly_pts, body_color.lightened(0.2))
	# Eyes — big and dark like a real seal
	for side in [-1.0, 1.0]:
		var ep := Vector2(side * 8, -8)
		draw_circle(ep, 5.5, Color(0.08, 0.06, 0.06))
		draw_circle(ep + Vector2(-1.0 * side, -1.2), 2.0, Color(1, 1, 1, 0.8))
	# Snout — rounded bump
	var snout_c := Vector2(0, 2)
	draw_circle(snout_c, 7.0, body_color.lightened(0.12))
	# Nose
	draw_circle(snout_c + Vector2(0, -1), 3.0, Color(0.2, 0.15, 0.15))
	# Whisker dots
	for dx in [-5.0, -3.0, 3.0, 5.0]:
		draw_circle(snout_c + Vector2(dx, 3), 1.0, body_color.darkened(0.3))

	# Carried fish (1 or 2) — drawn prominently above head
	if _fish_count >= 1:
		_draw_carried_fish(Vector2(-12, -RADIUS - 14) if _fish_count > 1 else Vector2(0, -RADIUS - 14))
	if _fish_count >= 2:
		_draw_carried_fish(Vector2(12, -RADIUS - 22))

func _draw_carried_fish(fp: Vector2) -> void:
	# Glow behind fish for visibility
	draw_circle(fp + Vector2(2, 0), 16.0, Color(1.0, 0.8, 0.2, 0.25))
	# Body ellipse
	var fish_pts: PackedVector2Array = []
	for fi in range(16):
		var angle := TAU * fi / 16.0
		fish_pts.append(fp + Vector2(cos(angle) * 12, sin(angle) * 7))
	draw_colored_polygon(fish_pts, Color(1.0, 0.65, 0.1))
	# Outline
	draw_polyline(fish_pts, Color(0.8, 0.4, 0.0), 1.5)
	# Tail
	draw_colored_polygon([fp + Vector2(10, 0), fp + Vector2(17, -6), fp + Vector2(17, 6)], Color(1.0, 0.6, 0.05))
	# Eye
	draw_circle(fp + Vector2(-4, -2), 2.0, Color.WHITE)
	draw_circle(fp + Vector2(-4, -2), 1.0, Color.BLACK)

func _physics_process(delta: float) -> void:
	if _is_in_water:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return

	# Invincibility flash after respawn
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			visible = true
		else:
			visible = fmod(_flash_timer, 0.2) > 0.1

	if _bounce_stun > 0.0:
		_bounce_stun -= delta

	var input_dir := _get_input()

	# Braking: input opposes velocity → stronger acceleration, but always in player's direction
	var is_braking := input_dir.length() > 0.1 and velocity.length() > 10.0 and input_dir.dot(velocity.normalized()) < -0.3

	if _bounce_stun <= 0.0 and input_dir.length() > 0.1:
		var accel := BRAKE_ACCEL if is_braking else ACCEL
		velocity += input_dir * accel * delta

	# Very light friction (25% of original)
	velocity *= 0.996
	if velocity.length() < 2.0:
		velocity = Vector2.ZERO

	if _bump_cooldown > 0.0:
		_bump_cooldown -= delta

	_last_ice_pos = global_position
	var pre_velocity := velocity
	var pre_position := global_position
	move_and_slide()

	# Speed factor: long run-up (high speed) = powerful bounce, short = weak
	var speed := pre_velocity.length()
	var speed_factor := clampf(speed / 400.0, 0.05, 1.0)
	var _hit_penguin := false

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is CharacterBody2D and other != self:
			# Bear is deadly — instant kill
			if other.has_method("is_deadly") and other.is_deadly():
				var away: Vector2 = (global_position - other.global_position).normalized()
				velocity = away * 200.0
				killed_by_enemy.emit(player_index)
				fall_in_water()
				return
			# Always mark light NPCs for pass-through, even during bump cooldown
			var is_light: bool = other.has_method("collect_fish") and not other.has_method("_set_bounce_stun")
			if is_light:
				_hit_penguin = true
			if _bump_cooldown <= 0.0:
				var normal: Vector2 = (other.global_position - global_position).normalized()
				var my_vel: Vector2 = pre_velocity
				var other_vel: Vector2 = other.velocity
				var my_along: float = my_vel.dot(normal)
				var other_along: float = other_vel.dot(normal)

				if is_light:
					# Hockey check — penguin gets launched, seal unaffected
					var launch: float = absf(my_along) * 3.0 * speed_factor + speed * 0.8
					launch = maxf(launch, 120.0)  # minimum push even at low speed
					other.velocity = normal * launch
					velocity = my_vel  # seal passes through penguin
					_hit_penguin = true
					# Rob the penguin if it has a fish — award to this seal
					if other.has_method("drop_fish") and other._has_fish:
						other.drop_fish()
						collect_penguin_fish()
				elif other.has_method("_power_hit") and speed_factor > 0.5:
					# Fast charge — launch walrus hard
					var launch_speed := speed * 1.5 * speed_factor
					other._power_hit(normal * launch_speed, 0.4 * speed_factor)
					velocity = -pre_velocity.normalized() * speed * 0.3  # recoil
					_bounce_stun = 0.3 * speed_factor
				else:
					# Elastic collision — mass-weighted (equal mass = swap components)
					var damping := 0.8 * speed_factor
					var m1 := 1.0  # seal mass
					var m2 := 1.0
					if other.has_method("get_mass"):
						m2 = other.get_mass()
					var m_total := m1 + m2
					var w1 := 2.0 * m2 / m_total  # how much self is affected
					var w2 := 2.0 * m1 / m_total  # how much other is affected
					velocity = my_vel - normal * my_along * w1 + normal * (other_along * damping * w1)
					other.velocity = other_vel - normal * other_along * w2 + normal * (my_along * damping * w2)
					_bounce_stun = 0.2 * speed_factor
					if other.has_method("_set_bounce_stun"):
						other._set_bounce_stun(0.2 * speed_factor)
					# Powerful hit knocks fish loose
					if speed_factor > 0.4 and other.has_method("drop_fish") and other.get("_has_fish"):
						other.drop_fish()

				_bump_cooldown = 0.15
				if other.has_method("_set_bump_cooldown"):
					other._set_bump_cooldown(0.15)
		elif other is StaticBody2D:
			var impact := absf(pre_velocity.dot(col.get_normal()))
			if impact > 80.0:
				# Hard hit — bounce off wall (no stun — velocity reflection is enough,
				# stun + held input creates a vibration loop against walls)
				velocity = pre_velocity.bounce(col.get_normal()) * 0.85

	# Penguin shouldn't block seal — restore intended position
	if _hit_penguin:
		global_position = pre_position + pre_velocity * delta

func _get_input() -> Vector2:
	var dir := Vector2.ZERO
	dir.x = Input.get_axis(_input_prefix + "left", _input_prefix + "right")
	dir.y = Input.get_axis(_input_prefix + "up", _input_prefix + "down")
	if dir.length() > 1.0:
		dir = dir.normalized()
	return dir

## Called by arena when seal enters water zone.
func fall_in_water() -> void:
	if _is_in_water:
		return
	if _has_fish:
		_drop_fish_at(_last_ice_pos)
	_is_in_water = true
	_respawn_timer = 1.5
	velocity = Vector2.ZERO
	visible = false
	fell_in_water.emit(player_index)

func _respawn() -> void:
	_is_in_water = false
	_flash_timer = 1.0
	velocity = Vector2.ZERO
	# Ensure fish state is clean
	_has_fish = false
	_fish_count = 0
	_fish_origins.clear()
	queue_redraw()
	var arena = get_parent()
	if arena.has_method("get_respawn_position"):
		global_position = arena.get_respawn_position(player_index)
	visible = true
	if arena.has_method("_spawn_splash"):
		arena._spawn_splash(global_position, 1)  # SEAL_OUT

func _set_bump_cooldown(t: float) -> void:
	_bump_cooldown = t

func _set_bounce_stun(t: float) -> void:
	_bounce_stun = t

## Called by fish when collected.
func collect_fish() -> void:
	if _is_in_water or _flash_timer > 0.0 or _fish_count >= MAX_FISH:
		return
	_fish_count += 1
	_fish_origins.append("ground")
	_has_fish = true
	queue_redraw()

## Called when penguin fish is robbed.
func collect_penguin_fish() -> void:
	if _is_in_water or _flash_timer > 0.0 or _fish_count >= MAX_FISH:
		return
	_fish_count += 1
	_fish_origins.append("penguin")
	_has_fish = true
	queue_redraw()

## Called by arena when seal reaches home — delivers one fish at a time.
func deliver_fish() -> void:
	if _fish_count <= 0:
		return
	var origin: String = _fish_origins.pop_front()
	_fish_count -= 1
	_has_fish = _fish_count > 0
	queue_redraw()
	fish_delivered.emit(player_index, origin)

## Drop all fish on powerful bounce.
func drop_fish() -> void:
	_drop_fish_at(global_position)

func _drop_fish_at(pos: Vector2) -> void:
	if _fish_count <= 0:
		return
	var count := _fish_count
	_fish_count = 0
	_fish_origins.clear()
	_has_fish = false
	queue_redraw()
	for _i in range(count):
		fish_dropped_by_player.emit(pos, player_index)
