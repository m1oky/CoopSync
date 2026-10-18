@tool
extends EditorPlugin

var dock_instance: Control
var net_instance: Node

const DockScript = preload("res://addons/coop_sync/dock.gd")
const NetScript = preload("res://addons/coop_sync/network.gd")

func _enter_tree() -> void:
	var root = get_tree().root
	if root.has_node("CoopSyncNet"):
		root.get_node("CoopSyncNet").free()
		
	net_instance = NetScript.new()
	net_instance.name = "CoopSyncNet"
	net_instance.editor_plugin = self
	root.add_child(net_instance)

	dock_instance = DockScript.new()
	dock_instance.editor_plugin = self
	dock_instance.net = net_instance
	net_instance.dock = dock_instance
	dock_instance.name = "CoopSync"
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock_instance)

	scene_saved.connect(_on_scene_saved)

func _exit_tree() -> void:
	if scene_saved.is_connected(_on_scene_saved):
		scene_saved.disconnect(_on_scene_saved)
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.free()
	if net_instance:
		net_instance.free()

func _on_scene_saved(filepath: String) -> void:
	if net_instance and net_instance.auto_sync_enabled:
		net_instance.sync_file(filepath)
