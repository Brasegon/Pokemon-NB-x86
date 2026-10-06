class_name G3DMaterials
extends RefCounted
## Matériaux Godot qui imitent le moteur 3D de la DS : couleur des sommets (ou éclairage DS
## calculé sur les normales) modulée par la texture, opacité du matériau, faces visibles,
## répétition et miroir des textures, matrice de texture (animations NSBTA).
##
## Éclairage de la DS (jusqu'à 4 lumières directionnelles, calcul par sommet) :
##   couleur = émission + somme des lumières allumées de
##             diffus x couleur x max(0, -L.N) + spéculaire x couleur x max(0, -H.N)² + ambiant x couleur
## avec H = (L + (0, 0, -1)) / 2 dans le repère de la caméra. Les calculs se font sur les couleurs de
## la DS (sRGB), converties ensuite pour Godot.
##
## Les coordonnées de texture des sommets sont en texels, comme sur la DS : le shader les divise
## par la taille de la texture courante (une animation NSBTP peut en changer).

enum Wrap { CLAMP, REPEAT, MIRROR }

## Lumière par défaut (celle du terrain de N&B en journée), dans le repère du monde.
const LIGHT_DIRECTION := Vector3(-0.47, -0.87, -0.07)
const LIGHT_COLOR := Color.WHITE

const _SHADER := """shader_type spatial;
render_mode unshaded, %s;

uniform sampler2D ds_texture : source_color, filter_nearest, repeat_disable;
uniform bool has_texture = false;
uniform vec2 texture_size = vec2(8.0);
uniform ivec2 wrap_mode = ivec2(0);
uniform vec2 tex_scale = vec2(1.0);
uniform float tex_rotation = 0.0;
uniform vec2 tex_translation = vec2(0.0);
uniform int polygon_mode = 0;
uniform float opacity = 1.0;
uniform bool alpha_test = false;
uniform bool lit = false;
uniform int light_mask = 1;
uniform vec3 light_directions[4];
uniform vec3 light_colors[4];
uniform vec3 diffuse = vec3(1.0);
uniform vec3 ambient = vec3(0.0);
uniform vec3 specular = vec3(0.0);
uniform vec3 emission = vec3(0.0);
// Fondu des palettes des textures (combat, 0x021F9304) : couleur visée (sRGB) et force evy / 16.
uniform vec4 palette_fade = vec4(0.0);

varying vec4 ds_color;

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

vec3 to_srgb(vec3 c) {
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}

float wrap_coord(float x, int mode) {
	if (mode == 1) {
		return fract(x);
	}
	if (mode == 2) {
		float m = mod(x, 2.0);
		return m > 1.0 ? 2.0 - m : m;
	}
	return clamp(x, 0.0, 1.0);
}

void vertex() {
	vec3 c = COLOR.rgb;
	if (lit) {
		vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		c = emission;
		for (int i = 0; i < 4; i++) {
			if ((light_mask & (1 << i)) == 0) {
				continue;
			}
			vec3 l = normalize((VIEW_MATRIX * vec4(light_directions[i], 0.0)).xyz);
			vec3 h = (l + vec3(0.0, 0.0, -1.0)) * 0.5;
			float shine = max(dot(-h, n), 0.0);
			c += light_colors[i] * (diffuse * max(dot(-l, n), 0.0) + specular * shine * shine + ambient);
		}
		c = min(c, vec3(1.0));
	}
	ds_color = vec4(to_linear(c), 1.0);
}

void fragment() {
	vec4 c = ds_color;
	if (has_texture) {
		vec2 uv = UV / texture_size * tex_scale;
		float s = sin(tex_rotation);
		float k = cos(tex_rotation);
		uv = vec2(uv.x * k - uv.y * s, uv.x * s + uv.y * k) - tex_translation;
		uv = vec2(wrap_coord(uv.x, wrap_mode.x), wrap_coord(uv.y, wrap_mode.y));
		vec4 t = texture(ds_texture, uv);
		if (palette_fade.a > 0.0) {
			// Mélange de la DS sur 5 bits (0x02021F00) : c + ((but - c) x evy >> 4).
			vec3 c5 = round(to_srgb(t.rgb) * 31.0);
			vec3 t5 = round(palette_fade.rgb * 31.0);
			t.rgb = to_linear((c5 + floor((t5 - c5) * palette_fade.a)) / 31.0);
		}
		if (polygon_mode == 1) {
			c.rgb = mix(c.rgb, t.rgb, t.a);
		} else {
			c *= t;
		}
	}
	ALBEDO = c.rgb;
	%s
}
"""

static var _shaders := {}


## Shader pour un mode de faces (« cull_back »...) et un mode de transparence :
## 0 = opaque (avec découpe des pixels transparents), 1 = translucide, 2 = translucide qui écrit
## la profondeur (indicateur de la DS pour certains polygones translucides).
static func shader(cull: String, transparency: int) -> Shader:
	var key := "%s/%d" % [cull, transparency]
	if not _shaders.has(key):
		var modes := cull
		var alpha_code := "if (alpha_test && c.a < 0.5) {\n\t\tdiscard;\n\t}"
		if transparency == 1:
			modes += ", blend_mix, depth_draw_opaque"
			alpha_code = "ALPHA = c.a * opacity;"
		elif transparency == 2:
			modes += ", blend_mix, depth_draw_always"
			alpha_code = "ALPHA = c.a * opacity;"
		var s := Shader.new()
		s.code = _SHADER % [modes, alpha_code]
		_shaders[key] = s
	return _shaders[key]


## Matériau Godot pour un matériau DS. `texture` peut être null ; `format` est le format de la
## texture (NSBTX.Format) pour savoir si elle a de la transparence. Renvoie null pour un matériau
## qui n'affiche rien (aucune face visible, polygones d'ombre, opacité 0 : le jeu ne le dessine
## pas), sauf si `force_translucent` le demande (opacité animée par une NSBMA).
static func create(mat: Dictionary, lit: bool, texture: Texture2D = null, format := 0, transparent_zero := false, force_translucent := false) -> ShaderMaterial:
	if not mat.show_front and not mat.show_back:
		return null
	if mat.polygon_mode == 3 or (mat.alpha == 0 and not force_translucent):
		return null
	var translucent: bool = force_translucent or mat.alpha < 31 or (texture != null and format in [NSBTX.Format.A3I5, NSBTX.Format.A5I3])
	var m := ShaderMaterial.new()
	m.shader = _shader_for(mat, translucent)
	m.set_meta("translucent", translucent)
	m.set_shader_parameter("opacity", mat.alpha / 31.0)
	m.set_shader_parameter("polygon_mode", mat.polygon_mode)
	m.set_shader_parameter("wrap_mode", Vector2i(_wrap(mat.repeat_s, mat.flip_s), _wrap(mat.repeat_t, mat.flip_t)))
	m.set_shader_parameter("lit", lit)
	m.set_shader_parameter("diffuse", _rgb(mat.diffuse))
	m.set_shader_parameter("ambient", _rgb(mat.ambient))
	m.set_shader_parameter("specular", _rgb(mat.specular))
	m.set_shader_parameter("emission", _rgb(mat.emission))
	m.set_shader_parameter("light_mask", mat.lights)
	m.set_shader_parameter("light_directions", PackedVector3Array([LIGHT_DIRECTION, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN]))
	m.set_shader_parameter("light_colors", PackedVector3Array([_rgb(LIGHT_COLOR), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]))
	set_texture_matrix(m, mat.tex_scale, mat.tex_rotation, mat.tex_translation)
	set_texture(m, texture, format == NSBTX.Format.COMPRESSED_4X4 or transparent_zero)
	return m


## Shader d'un matériau DS : faces visibles et transparence.
static func _shader_for(mat: Dictionary, translucent: bool) -> Shader:
	var cull := "cull_disabled"
	if mat.show_front and not mat.show_back:
		cull = "cull_back"
	elif mat.show_back and not mat.show_front:
		cull = "cull_front"
	var transparency := 0
	if translucent:
		transparency = 2 if mat.translucent_depth else 1
	return shader(cull, transparency)


static func is_translucent(m: ShaderMaterial) -> bool:
	return m.get_meta("translucent", false)


## Copie translucide d'un matériau (pour animer son opacité), avec les mêmes réglages.
static func translucent_copy(m: ShaderMaterial, mat: Dictionary) -> ShaderMaterial:
	var copy := ShaderMaterial.new()
	copy.shader = _shader_for(mat, true)
	copy.set_meta("translucent", true)
	for uniform: Dictionary in m.shader.get_shader_uniform_list():
		var uniform_name: String = uniform.name
		copy.set_shader_parameter(uniform_name, m.get_shader_parameter(uniform_name))
	return copy


## Couleurs et opacité d'une animation NSBMA : opacité de 0 à 31 (-1 : inchangée) ; les couleurs ne
## changent que l'éclairage (matériaux éclairés).
static func set_colors(m: ShaderMaterial, alpha: int, diffuse: Color, ambient: Color, specular: Color, emission: Color) -> void:
	if alpha >= 0:
		m.set_shader_parameter("opacity", alpha / 31.0)
	m.set_shader_parameter("diffuse", _rgb(diffuse))
	m.set_shader_parameter("ambient", _rgb(ambient))
	m.set_shader_parameter("specular", _rgb(specular))
	m.set_shader_parameter("emission", _rgb(emission))


## Applique un éclairage (voir FieldLight.sample()) : lumières allumées, couleurs et directions,
## et, si `override_colors`, les couleurs imposées aux matériaux. `mask` = lumières du matériau.
static func apply_light(m: ShaderMaterial, light: Dictionary, mask: int, override_colors := true) -> void:
	var directions := PackedVector3Array()
	var colors := PackedVector3Array()
	var enabled := 0
	for i in 4:
		directions.append(light.directions[i])
		colors.append(_rgb(light.colors[i]))
		if light.enabled[i]:
			enabled |= 1 << i
	m.set_shader_parameter("light_directions", directions)
	m.set_shader_parameter("light_colors", colors)
	m.set_shader_parameter("light_mask", mask & enabled)
	if override_colors:
		for name in ["diffuse", "ambient", "specular", "emission"]:
			m.set_shader_parameter(name, _rgb(light[name]))


## Change la texture d'un matériau (animations NSBTP).
static func set_texture(m: ShaderMaterial, texture: Texture2D, alpha_test := true) -> void:
	m.set_shader_parameter("has_texture", texture != null)
	m.set_shader_parameter("alpha_test", alpha_test)
	if texture:
		m.set_shader_parameter("ds_texture", texture)
		m.set_shader_parameter("texture_size", Vector2(texture.get_size()))


## Matrice de texture en coordonnées normalisées (animations NSBTA).
static func set_texture_matrix(m: ShaderMaterial, scale: Vector2, rotation: float, translation: Vector2) -> void:
	m.set_shader_parameter("tex_scale", scale)
	m.set_shader_parameter("tex_rotation", rotation)
	m.set_shader_parameter("tex_translation", translation)


static func _wrap(repeat: bool, flip: bool) -> int:
	if not repeat:
		return Wrap.CLAMP
	return Wrap.MIRROR if flip else Wrap.REPEAT


static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
