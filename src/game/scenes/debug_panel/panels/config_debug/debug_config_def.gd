class_name DebugConfigDef
extends Resource

## One game config a designer tunes in the debug "Конфиги" tab. Every new designer config gets
## one of these in `config_debug_tab.tscn` → `configs`.

## Sub-tab title.
@export var title: String = ""
## The game's default config file (.tres): its number / flag exports become the editor's fields,
## "Сохранить" writes into it.
@export var config: Resource
## Key in `VolleySim.cfg` the battle copies this config into at match start ("physics", "arena",
## "rules"): "Включено" then writes into the running battle's copy. "" = the game reads the
## Resource itself, so "Включено" changes the loaded Resource in memory.
@export var sim_section: String = ""
## Extra line for the save confirmation (what else changes when this default changes).
@export_multiline var save_note: String = ""
