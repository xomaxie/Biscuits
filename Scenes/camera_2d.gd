extends Camera2D

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
enum FitMode { MATCH_HEIGHT, MATCH_WIDTH, EXPAND_SMART }

@export var reference_size: Vector2i = Vector2i(1920, 1080)
@export var fit_mode: FitMode = FitMode.MATCH_HEIGHT
@export var min_zoom: float = 0.35
@export var max_zoom: float = 3.0
@export var pixel_snap: bool = true

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_update_zoom()
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_update_zoom)

# -----------------------------------------------------------------------------
# Zoom logic
# -----------------------------------------------------------------------------
func _update_zoom() -> void:
	var vp_size := get_viewport_rect().size
	if reference_size.x <= 0 or reference_size.y <= 0:
		return

	var z: float = 1.0
	match fit_mode:
		FitMode.MATCH_HEIGHT:
			z = float(vp_size.y) / float(reference_size.y)
		FitMode.MATCH_WIDTH:
			z = float(vp_size.x) / float(reference_size.x)
		FitMode.EXPAND_SMART:
			var zx := float(vp_size.x) / float(reference_size.x)
			var zy := float(vp_size.y) / float(reference_size.y)
			z = min(zx, zy)

	z = clamp(z, min_zoom, max_zoom)
	if pixel_snap:
		z = max(0.001, round(z * 1000.0) / 1000.0)

	zoom = Vector2(z, z)
