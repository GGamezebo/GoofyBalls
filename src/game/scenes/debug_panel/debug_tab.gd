class_name DebugTab
extends VBoxContainer

## Base of a debug panel tab (the root node of its scene). The panel creates the tab when its
## target appears (`DebugTabDef.target_scene`) and frees it when the target leaves the tree;
## an `always_open` tab is made once (target null) and hears its target in `on_target_changed`.
## Debug code may read and change the target's private fields: game code never knows about tabs.

## Set by the panel before `attach`.
var log_channel: LogChannel


## false = nothing to show for this target (e.g. the "Сеть" tab in an offline battle).
## Called after the target's `initialize`, before `attach`.
func accepts(_target: Node) -> bool:
	return true


## `target` = the scene this tab works on (null for a tab without a target). `memory` = this
## tab's own Dictionary, kept by the panel across targets (what the user set last time).
func attach(_target: Node, _memory: Dictionary) -> void:
	pass


## The target is leaving the tree: undo whatever the tab changed outside the target.
func detach() -> void:
	pass


## `always_open` tabs only: their target entered the tree (after its `initialize`) or left (null).
func on_target_changed(_target: Node) -> void:
	pass
