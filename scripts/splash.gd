extends Node2D
## Animated water splash effect — spawned at a position, plays once, then frees itself.
## Different presets for different creatures and directions (in/out of water).

enum Kind { SEAL_IN, SEAL_OUT, PENGUIN_IN, PENGUIN_OUT, BEAR_IN, BEAR_OUT }

var kind: Kind = Kind.SEAL_IN
var _time := 0.0
var _lifetime := 0.0
var _particles: Array[Dictionary] = []

func _ready() -> void:
	z_index = 15
	match kind:
		Kind.SEAL_IN:
			_setup_seal_plunge()
		Kind.SEAL_OUT:
			_setup_seal_emerge()
		Kind.PENGUIN_IN:
			_setup_penguin_plop()
		Kind.PENGUIN_OUT:
			_setup_penguin_hop_out()
		Kind.BEAR_IN:
			_setup_bear_crash()
		Kind.BEAR_OUT:
			_setup_bear_surge()

func _setup_seal_plunge() -> void:
	## Big heavy splash — wide ring of droplets bursting outward + central column
	_lifetime = 0.9
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Ring of heavy droplets
	for i in range(16):
		var angle := TAU * i / 16.0 + rng.randf_range(-0.15, 0.15)
		var speed := rng.randf_range(120, 220)
		var sz := rng.randf_range(4.0, 8.0)
		_particles.append({
			pos = Vector2.ZERO,
			vel = Vector2(cos(angle), sin(angle)) * speed + Vector2(0, -speed * 0.4),
			gravity = 350.0,
			size = sz,
			max_size = sz,
			color = Color(0.6, 0.8, 1.0, 0.9),
			life = rng.randf_range(0.5, 0.8),
		})
	# Central water column (upward spray)
	for i in range(8):
		var spread := rng.randf_range(-30, 30)
		var speed := rng.randf_range(180, 300)
		_particles.append({
			pos = Vector2(spread, 0),
			vel = Vector2(rng.randf_range(-20, 20), -speed),
			gravity = 400.0,
			size = rng.randf_range(3.0, 6.0),
			max_size = rng.randf_range(3.0, 6.0),
			color = Color(0.7, 0.85, 1.0, 0.85),
			life = rng.randf_range(0.4, 0.7),
		})
	# Expanding ring (ripple)
	_particles.append({
		pos = Vector2.ZERO,
		vel = Vector2.ZERO,
		gravity = 0.0,
		size = 10.0,
		max_size = 80.0,
		color = Color(0.5, 0.75, 1.0, 0.6),
		life = 0.7,
		ring = true,
	})

func _setup_seal_emerge() -> void:
	## Upward burst — water shedding off as seal rises
	_lifetime = 0.7
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Upward fountain
	for i in range(12):
		var angle := rng.randf_range(-PI * 0.8, -PI * 0.2)  # mostly upward
		var speed := rng.randf_range(80, 160)
		_particles.append({
			pos = Vector2(rng.randf_range(-15, 15), 0),
			vel = Vector2(cos(angle), sin(angle)) * speed,
			gravity = 300.0,
			size = rng.randf_range(2.5, 5.5),
			max_size = rng.randf_range(2.5, 5.5),
			color = Color(0.65, 0.82, 1.0, 0.8),
			life = rng.randf_range(0.35, 0.6),
		})
	# Small ripple
	_particles.append({
		pos = Vector2.ZERO,
		vel = Vector2.ZERO,
		gravity = 0.0,
		size = 5.0,
		max_size = 50.0,
		color = Color(0.5, 0.75, 1.0, 0.4),
		life = 0.5,
		ring = true,
	})

func _setup_penguin_plop() -> void:
	## Small cute splash — light scatter of tiny droplets
	_lifetime = 0.6
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(10):
		var angle := TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)
		var speed := rng.randf_range(60, 120)
		_particles.append({
			pos = Vector2.ZERO,
			vel = Vector2(cos(angle), sin(angle)) * speed + Vector2(0, -speed * 0.3),
			gravity = 280.0,
			size = rng.randf_range(2.0, 4.0),
			max_size = rng.randf_range(2.0, 4.0),
			color = Color(0.7, 0.85, 1.0, 0.85),
			life = rng.randf_range(0.3, 0.5),
		})
	# Tiny ripple
	_particles.append({
		pos = Vector2.ZERO,
		vel = Vector2.ZERO,
		gravity = 0.0,
		size = 5.0,
		max_size = 35.0,
		color = Color(0.55, 0.78, 1.0, 0.45),
		life = 0.45,
		ring = true,
	})

func _setup_penguin_hop_out() -> void:
	## Small upward scatter — penguin jumping out of water
	_lifetime = 0.5
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(8):
		var angle := rng.randf_range(-PI * 0.85, -PI * 0.15)
		var speed := rng.randf_range(50, 100)
		_particles.append({
			pos = Vector2(rng.randf_range(-8, 8), 0),
			vel = Vector2(cos(angle), sin(angle)) * speed,
			gravity = 250.0,
			size = rng.randf_range(1.5, 3.5),
			max_size = rng.randf_range(1.5, 3.5),
			color = Color(0.65, 0.82, 1.0, 0.75),
			life = rng.randf_range(0.25, 0.45),
		})

func _setup_bear_crash() -> void:
	## Massive splash — tidal wave ring, heavy spray, screen-shake-worthy
	_lifetime = 1.2
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Big ring of heavy droplets
	for i in range(24):
		var angle := TAU * i / 24.0 + rng.randf_range(-0.12, 0.12)
		var speed := rng.randf_range(150, 320)
		var sz := rng.randf_range(5.0, 11.0)
		_particles.append({
			pos = Vector2.ZERO,
			vel = Vector2(cos(angle), sin(angle)) * speed + Vector2(0, -speed * 0.3),
			gravity = 320.0,
			size = sz,
			max_size = sz,
			color = Color(0.55, 0.78, 1.0, 0.9),
			life = rng.randf_range(0.6, 1.0),
		})
	# Tall water column
	for i in range(12):
		var spread := rng.randf_range(-40, 40)
		_particles.append({
			pos = Vector2(spread, 0),
			vel = Vector2(rng.randf_range(-30, 30), -rng.randf_range(250, 420)),
			gravity = 380.0,
			size = rng.randf_range(4.0, 8.0),
			max_size = rng.randf_range(4.0, 8.0),
			color = Color(0.6, 0.82, 1.0, 0.85),
			life = rng.randf_range(0.5, 0.9),
		})
	# Big expanding ripple
	_particles.append({
		pos = Vector2.ZERO,
		vel = Vector2.ZERO,
		gravity = 0.0,
		size = 15.0,
		max_size = 120.0,
		color = Color(0.45, 0.7, 0.95, 0.55),
		life = 0.9,
		ring = true,
	})
	# Second smaller ripple delayed
	_particles.append({
		pos = Vector2.ZERO,
		vel = Vector2.ZERO,
		gravity = 0.0,
		size = 0.0,
		max_size = 80.0,
		color = Color(0.5, 0.75, 1.0, 0.4),
		life = 0.7,
		ring = true,
		delay = 0.15,
	})

func _setup_bear_surge() -> void:
	## Bear climbing out — heavy water cascading off, ground-level spray
	_lifetime = 0.9
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Cascading water
	for i in range(16):
		var angle := rng.randf_range(-PI * 0.9, -PI * 0.1)
		var speed := rng.randf_range(100, 200)
		_particles.append({
			pos = Vector2(rng.randf_range(-25, 25), rng.randf_range(-10, 10)),
			vel = Vector2(cos(angle), sin(angle)) * speed,
			gravity = 350.0,
			size = rng.randf_range(3.5, 7.0),
			max_size = rng.randf_range(3.5, 7.0),
			color = Color(0.6, 0.8, 1.0, 0.8),
			life = rng.randf_range(0.4, 0.7),
		})
	# Ground spray (sideways)
	for i in range(8):
		var side := -1.0 if i < 4 else 1.0
		_particles.append({
			pos = Vector2.ZERO,
			vel = Vector2(side * rng.randf_range(60, 140), rng.randf_range(-20, 20)),
			gravity = 200.0,
			size = rng.randf_range(2.0, 4.5),
			max_size = rng.randf_range(2.0, 4.5),
			color = Color(0.65, 0.82, 1.0, 0.7),
			life = rng.randf_range(0.3, 0.55),
		})
	# Medium ripple
	_particles.append({
		pos = Vector2.ZERO,
		vel = Vector2.ZERO,
		gravity = 0.0,
		size = 10.0,
		max_size = 70.0,
		color = Color(0.5, 0.75, 1.0, 0.45),
		life = 0.6,
		ring = true,
	})

func _process(delta: float) -> void:
	_time += delta
	if _time >= _lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	for p in _particles:
		var delay: float = p.get("delay", 0.0)
		if _time < delay:
			continue
		var t: float = _time - delay
		var life: float = p["life"]
		if t > life:
			continue
		var frac: float = t / life
		var vel: Vector2 = p["vel"]
		var grav: float = p["gravity"]
		var base_pos: Vector2 = p["pos"]
		var col: Color = p["color"]
		var pos: Vector2 = base_pos + vel * t + Vector2(0, 0.5 * grav * t * t)
		var alpha: float = col.a * (1.0 - frac * frac)  # fade out

		if p.get("ring", false):
			# Expanding ring
			var sz_min: float = p["size"]
			var sz_max: float = p["max_size"]
			var r: float = lerpf(sz_min, sz_max, frac)
			var width: float = lerpf(3.0, 1.0, frac)
			draw_arc(pos, r, 0, TAU, 24, Color(col, alpha), width)
		else:
			# Droplet — shrinks as it fades
			var sz: float = float(p["size"]) * (1.0 - frac * 0.6)
			draw_circle(pos, sz, Color(col, alpha))
