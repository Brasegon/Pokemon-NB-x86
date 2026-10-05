// Personnage du terrain : un panneau toujours face à l'écran, posé sur ses pieds (l'origine du
// nœud). Un panneau vertical vu en perspective penche vers le centre sur les bords de l'écran et
// s'élargit vers le haut ; celui-ci garde partout la forme de l'image. Sa profondeur reste celle
// d'un panneau vertical tourné vers la caméra et étiré pour couvrir la même hauteur à l'écran : le
// personnage passe derrière ce qui est devant lui sans s'enfoncer dans les murs derrière lui.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D frame : source_color, filter_nearest;

void vertex() {
	vec2 size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	// Position à l'écran : le rectangle de l'image, dans le plan de la caméra, autour des pieds.
	vec3 feet = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec4 facing = PROJECTION_MATRIX * vec4(feet + vec3(VERTEX.xy * size, 0.0), 1.0);
	// Profondeur : le panneau vertical, étiré de 1 / cos(inclinaison de la caméra). La composante
	// verticale de l'axe « haut » de la caméra vaut ce cosinus.
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	float stretch = 1.0 / max(INV_VIEW_MATRIX[1].y, 0.2);
	vec3 upright = MODEL_MATRIX[3].xyz + right * VERTEX.x * size.x + vec3(0.0, VERTEX.y * size.y * stretch, 0.0);
	vec4 depth = PROJECTION_MATRIX * VIEW_MATRIX * vec4(upright, 1.0);
	POSITION = vec4(facing.xy, depth.z / depth.w * facing.w, facing.w);
	// Teinte de l'heure (modulate), en sRGB comme pour un Sprite3D.
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

void fragment() {
	vec4 color = texture(frame, UV) * COLOR;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
