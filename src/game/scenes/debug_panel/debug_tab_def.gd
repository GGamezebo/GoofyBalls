class_name DebugTabDef
extends Resource

## One tab (subpanel) of the debug panel. The Resource itself is the tab id: a context enables or
## disables its tab by passing this `.tres` through `DebugEvents`.

## Tab title.
@export var title: String = ""
## Tab content (a Control scene). The debug panel instances it while the tab is enabled.
@export var scene: PackedScene
