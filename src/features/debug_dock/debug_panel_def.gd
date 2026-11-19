class_name DebugPanelDef
extends Resource

## One tab of the debug dock. The Resource itself is the panel id: a context enables or
## disables its tab by passing this `.tres` through `DebugEvents`.

## Tab title.
@export var title: String = ""
## Tab content (a Control scene). The dock instances it while the panel is enabled.
@export var scene: PackedScene
