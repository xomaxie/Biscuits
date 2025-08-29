extends CanvasLayer

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------
@export var layer_index: int = 100
@export var only_web: bool = false
@export var visible_on_start: bool = true
@export var contrast: float = 1.10
@export var saturation: float = 1.10
@export var brightness: float = 0.05

# -----------------------------------------------------------------------------
# Runtime State
# -----------------------------------------------------------------------------
var _rect: ColorRect
var _mat: ShaderMaterial

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	layer = layer_index
	if only_web and not OS.has_feature("web"):
		visible = false
		return
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rect.anchor_left = 0.0
	_rect.anchor_top = 0.0
	_rect.anchor_right = 1.0
	_rect.anchor_bottom = 1.0
	_rect.offset_left = 0.0
	_rect.offset_top = 0.0
	_rect.offset_right = 0.0
	_rect.offset_bottom = 0.0
	_mat = ShaderMaterial.new()
	_mat.shader = _make_shader()
	_rect.material = _mat
	add_child(_rect)
	visible = visible_on_start
	_apply_values()

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
func set_contrast(v: float) -> void:
	contrast = v
	_apply_values()

func set_saturation(v: float) -> void:
	saturation = v
	_apply_values()

func set_brightness(v: float) -> void:
	brightness = v
	_apply_values()

# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------
func _apply_values() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("contrast", contrast)
	_mat.set_shader_parameter("saturation", saturation)
	_mat.set_shader_parameter("brightness", brightness)

func _make_shader() -> Shader:
	var code := ""
	code += "shader_type canvas_item;\n"
	code += "uniform sampler2D screen_tex : hint_screen_texture;\n"
	code += "uniform float contrast = 1.1;\n"
	code += "uniform float saturation = 1.1;\n"
	code += "uniform float brightness = 0.05;\n"
	code += "void fragment(){\n"
	code += "vec3 c = texture(screen_tex, SCREEN_UV).rgb;\n"
	code += "float l = dot(c, vec3(0.299,0.587,0.114));\n"
	code += "c = mix(vec3(l), c, saturation);\n"
	code += "c = (c - 0.5) * contrast + 0.5;\n"
	code += "c += brightness;\n"
	code += "COLOR = vec4(c, 1.0);\n"
	code += "}\n"
	var sh := Shader.new()
	sh.code = code
	return sh
