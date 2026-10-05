class_name GameInput
extends RefCounted
## Petites aides pour les entrées (les actions elles-mêmes sont déclarées par l'autoload Controls).


## Vrai pour un clic gauche : la souris remplace l'écran tactile et le bouton A.
static func is_click(event: InputEvent) -> bool:
	var mouse := event as InputEventMouseButton
	return mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
