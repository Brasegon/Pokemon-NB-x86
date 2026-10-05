class_name FieldNpc
extends Node3D
## Un PNJ du terrain, posé d'après les événements de la zone : son sprite (fiche `a/0/4/8`, puis
## image dans `a/0/4/9`), son ombre, sa case et sa direction.

## Entrée des événements de la zone (numéro, sprite, script, direction, x, z, y...).
var data: Dictionary
var tile := Vector2i.ZERO
var facing := CharacterSprite.Direction.DOWN
var sprite: CharacterSprite
## Ses déplacements autonomes (code de mouvement des événements).
var movement: NpcMovement
## Reste au changement de zone (commande 0x241) : voir FieldMap._spawn_npcs().
var kept_on_zone_change := false


## PNJ d'après son entrée des événements ; textures = null le laisse sans sprite (objet 3D ou
## image introuvable), avec son ombre seulement.
static func create(entry: Dictionary, textures: NSBTX) -> FieldNpc:
	var npc := FieldNpc.new()
	npc.name = "PNJ_%d" % entry.id
	npc.data = entry
	npc.tile = Vector2i(entry.x, entry.z)
	npc.sprite = CharacterSprite.create(textures)
	if npc.sprite:
		npc.add_child(npc.sprite)
	npc.add_child(CharacterSprite.make_shadow())
	npc.face(clampi(entry.direction, 0, 3) as CharacterSprite.Direction)
	npc.movement = NpcMovement.create(entry)
	return npc


func face(direction: CharacterSprite.Direction) -> void:
	facing = direction
	if sprite:
		sprite.show_frame(facing, CharacterSprite.Step.STAND)
