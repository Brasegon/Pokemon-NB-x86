class_name ScreenFade
extends ColorRect
## Fondu de tout l'écran vers le noir ou le blanc : celui des portes, et celui des scripts (commande
## 0xB3), qui imite la luminosité de la DS (registres 0x0400006C et 0x0400106C, de -16 : noir, à
## +16 : blanc ; 0x0204E7BC les écrit).

const LEVELS := 16.0
## Le fondu de la luminosité avance à chaque image de l'écran (60 par seconde).
const SCREEN_FRAME := 1.0 / 60.0

var _tween: Tween


func _init() -> void:
	name = "Fondu"
	color = Color(0, 0, 0, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Fondu de l'opacité actuelle à `alpha` (0 à 1), vers le noir ou le blanc, en `duration` secondes.
func fade_to(alpha: float, duration: float, white := false) -> Signal:
	if _tween:
		_tween.kill()
	var tint := Color.WHITE if white else Color.BLACK
	color = Color(tint, color.a)
	_tween = create_tween()
	_tween.tween_property(self, "color:a", alpha, duration)
	return _tween.finished


## Fondu de luminosité comme 0x0204E6B8 : de `from` à `to` (en seizièmes, positif = blanc,
## négatif = noir), d'un cran toutes les `speed` images (ou de 1 - speed crans par image si speed
## est négatif).
func brightness(from: int, to: int, speed: int) -> Signal:
	var steps := absi(to - from)
	var frames := steps * maxi(speed, 1) if speed >= 0 else ceili(steps / (1.0 - speed))
	var white := (to if to != 0 else from) > 0
	color = Color(Color.WHITE if white else Color.BLACK, absf(from) / LEVELS)
	return fade_to(absf(to) / LEVELS, frames * SCREEN_FRAME, white)


func is_fading() -> bool:
	return _tween != null and _tween.is_running()
