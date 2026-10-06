// Rendu « façon DS » : la texture contient des index de couleur (R = octet de poids faible,
// G = octet de poids fort, pour les palettes étendues de plus de 256 couleurs) et la couleur
// vient de la texture de palette. Changer ou animer la palette ne demande aucun nouveau rendu.
shader_type canvas_item;

uniform sampler2D palette : filter_nearest, repeat_disable;
// Décalage ajouté à chaque index (choix d'une ligne de palette).
uniform int index_offset = 0;
// Couleur vers laquelle tirer l'image (alpha = force) : flash blanc d'un Pokémon qui sort de sa Ball.
uniform vec4 flash = vec4(1.0, 1.0, 1.0, 0.0);

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 raw = texture(TEXTURE, UV);
	int index = int(round(raw.r * 255.0)) + int(round(raw.g * 255.0)) * 256 + index_offset;
	ivec2 size = textureSize(palette, 0);
	vec4 color = texelFetch(palette, ivec2(index % size.x, index / size.x), 0);
	color.rgb = mix(color.rgb, flash.rgb, flash.a);
	COLOR = color * modulate;
}
