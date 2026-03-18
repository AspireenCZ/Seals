# Collectables Design

> Provenance: claude, 2026-03-11, session 41bc0d2b

## Fish — `fish.gd`

**Role:** The only collectable. Arc-jumps from water onto ice, sits until collected or expires.

### States

`JUMPING` → `LANDED` → `COLLECTED`

### Spawning (arena controls)

- Max 2 on field, 3-7s gaps between spawns, first spawn at 3.5s
- Landing strategy: 40% midpoint between players, 30% near center (away from players), 30% random ice
- Source: nearest ice edge or random hole center. Arc jump from source to landing.
- Dropped fish (from seal): spawns at seal's last ice position with short pop, no travel arc

### Arc jump

- Parabolic arc from source to landing. Default 0.6s duration, 80px height.
- Scale 0.5→1.0 during jump (fake perspective). Not collectible until landed.
- Landing: scale pop (1.3×0.7 → 1.0), monitoring enabled.

### Landed behavior

- Lifetime: 8s, then despawns (queue_free)
- Flop animation: gentle rotation oscillation
- Glow arc indicator (yellow ring) for visibility
- Collision: Area2D, layer 4, mask 2 (detects player bodies)

### Collection

- `body_entered` signal fires for any CharacterBody2D with `collect_fish()` method
- Guards: not in water, not flashing (invincible), not carrying max fish
- Collectors: **seal** (player, max 2), **penguin** (via script proximity, not Area2D), **bear** (via script proximity), **kid** (70px proximity check)
- Pop+fade tween on collect, then queue_free

### Origin tracking

- Each fish has `origin` string: `"ground"` (fresh spawn) or `"opponent"` (dropped by another seal)
- On collect from opponent-dropped fish: replaces the "ground" origin added by `collect_fish()` with "opponent"
- Origins stored as stack in seal's `_fish_origins` array — popped FIFO on delivery

### Visual

- Orange ellipse body (28×18px), tail triangle, white/black eye
- Landed: full opacity + glow ring. Jumping: 50% opacity
- Procedural `_draw()`, no sprites

### Interactions

| Who | How | Result |
|---|---|---|
| Seal | Area2D overlap | Collected, +1 to carry (max 2) |
| Penguin | Script proximity in `_find_nearest_fish()` | Collected, penguin starts leaving |
| Bear | Script proximity in `_find_nearest_fish()` | Eaten, `fish_stolen` signal (gone for good) |
| Kid | 70px proximity in `_try_eat_fish()` | Eaten directly, +1 score |
| Timeout | 8s landed | Despawns |
