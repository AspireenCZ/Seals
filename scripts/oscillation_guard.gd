extends Node
## Anti-oscillation guard. Add as child of any Node2D or CharacterBody2D.
## Detects when an object is moving but going nowhere (oscillating).
##
## Detection: over a sliding window, if total path length is large but
## the bounding box is small, the object is trapped in a loop. Kill velocity.
##
## Usage: parent_node.add_child(OscillationGuard.new())

const WINDOW := 16              # frames of position history (~0.27s at 60fps)
const MAX_SPREAD := 15.0        # px — bounding box limit to count as "going nowhere"
const MIN_PATH_RATIO := 3.0     # path_length / spread — how much wasted motion triggers it
const MIN_PATH_LENGTH := 15.0   # px — ignore objects that are barely moving
const CHECK_INTERVAL := 8       # only check every N frames (perf)

var _positions: Array[Vector2] = []
var _frame := 0

func _physics_process(_delta: float) -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return

	_positions.append(parent.global_position)
	if _positions.size() > WINDOW:
		_positions.pop_front()

	_frame += 1
	if _frame % CHECK_INTERVAL != 0:
		return
	if _positions.size() < WINDOW:
		return

	# Bounding box of all positions
	var min_p := _positions[0]
	var max_p := _positions[0]
	for p in _positions:
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var spread := maxf(max_p.x - min_p.x, max_p.y - min_p.y)

	if spread > MAX_SPREAD:
		return

	# Total path length (how much the object actually moved)
	var path_length := 0.0
	for i in range(1, _positions.size()):
		path_length += _positions[i].distance_to(_positions[i - 1])

	if path_length < MIN_PATH_LENGTH:
		return  # barely moving — not oscillating, just slow

	if path_length / maxf(spread, 0.1) >= MIN_PATH_RATIO:
		print("[%d] WARN: oscillation on %s at (%.0f, %.0f) — spread %.1fpx, path %.0fpx over %d frames" % [
			Time.get_ticks_msec(), parent.name, parent.global_position.x, parent.global_position.y,
			spread, path_length, WINDOW])
		# Stop all movement — CharacterBody2D velocity + any custom motion vars
		if parent is CharacterBody2D:
			parent.velocity = Vector2.ZERO
		if parent.has_method("stop_movement"):
			parent.stop_movement()
		_positions.clear()
		_frame = 0
