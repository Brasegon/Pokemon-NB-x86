// Rendu « façon DS » : la texture contient des index de couleur (R = octet de poids faible,
// G = octet de poids fort, pour les palettes étendues de plus de 256 couleurs) et la couleur
// vient de la texture de palette. Changer ou animer la palette ne demande aucun nouveau rendu.
shader_type canvas_item;

uniform sampler2D palette : filter_nearest, repeat_disable;
// Décalage ajouté à chaque index (choix d'une ligne de palette).
uniform int index_offset = 0;
// Couleur vers laquelle tirer l'image (alpha = force de 0 à 1, soit 0 à 16 sur DS) : fondu de palette
// des sprites du combat (0x02021F00 : c + ((cible - c) x force >> 4) sur 5 bits par composante).
uniform vec4 flash = vec4(1.0, 1.0, 1.0, 0.0);
// Sol qui cache le bas du sprite (sprites du combat en mode « monde », test de profondeur de la
// DS) : les pixels plus bas que clip_y (repère du nœud) ne sont pas dessinés.
uniform bool clip_enabled = false;
uniform float clip_y = 0.0;

varying vec4 modulate;
varying vec2 local_position;

void vertex() {
	modulate = COLOR;
	local_position = VERTEX;
}

void fragment() {
	if (clip_enabled && local_position.y > clip_y) {
		discard;
	}
	vec4 raw = texture(TEXTURE, UV);
	int index = int(round(raw.r * 255.0)) + int(round(raw.g * 255.0)) * 256 + index_offset;
	ivec2 size = textureSize(palette, 0);
	vec4 color = texelFetch(palette, ivec2(index % size.x, index / size.x), 0);
	if (flash.a > 0.0) {
		vec3 c5 = round(color.rgb * 31.0);
		vec3 t5 = round(flash.rgb * 31.0);
		color.rgb = (c5 + floor((t5 - c5) * flash.a)) / 31.0;
	}
	COLOR = color * modulate;
}
