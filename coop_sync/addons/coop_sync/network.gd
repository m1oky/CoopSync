@tool
extends Node

var editor_plugin: EditorPlugin
var dock: Control

var peer: ENetMultiplayerPeer
var is_host: bool = false
var auto_sync_enabled: bool = true
var create_backup: bool = true

var connected_peers: Dictionary = {}
var avatars: Dictionary = {}
var selection_boxes: Dictionary = {}

var heartbeat_timer: Timer
var peer_last_seen: Dictionary = {}

var last_cam_pos: Vector3 = Vector3.ZERO
var last_cam_basis: Basis = Basis.IDENTITY
var last_selected_path: NodePath = NodePath("")
var my_custom_color: Color = Color(0.2, 0.75, 1.0)

func _ready() -> void:
	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = 1.0
	heartbeat_timer.autostart = false
	heartbeat_timer.timeout.connect(_on_heartbeat_tick)
	add_child(heartbeat_timer)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not editor_plugin:
		return

	# Прямая передача перемещения камеры без задержек
	var iface = editor_plugin.get_editor_interface()
	var vp = iface.get_editor_viewport_3d(0)
	if vp:
		var cam = vp.get_camera_3d()
		if cam:
			var c_pos = cam.global_position
			var c_basis = cam.global_transform.basis
			if c_pos.distance_squared_to(last_cam_pos) > 0.0001 or not c_basis.is_equal_approx(last_cam_basis):
				last_cam_pos = c_pos
				last_cam_basis = c_basis
				rpc("rpc_update_cursor", multiplayer.get_unique_id(), c_pos, c_basis)

	# Отслеживание выделения узла в 3D
	var selection = iface.get_selection().get_selected_nodes()
	var current_path = NodePath("")
	if selection.size() > 0:
		var edited_root = iface.get_edited_scene_root()
		if edited_root and edited_root.is_ancestor_of(selection[0]):
			current_path = edited_root.get_path_to(selection[0])
	
	if current_path != last_selected_path:
		last_selected_path = current_path
		rpc("rpc_update_selection", multiplayer.get_unique_id(), current_path)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop_session("Закрытие окна")

func log_msg(text: String) -> void:
	if dock:
		dock.log_msg(text)

func update_ui_user_list() -> void:
	if dock:
		dock.refresh_users(connected_peers)

func start_host(port: int) -> void:
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, 8)
	if err != OK:
		log_msg("Ошибка создания сервера на порту %d" % port)
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	
	var my_name = dock.name_input.text.strip_edges() if dock else "Host"
	if my_name == "":
		my_name = "Host"
	connected_peers[1] = {"name": my_name, "is_host": true, "color": my_custom_color}
	update_ui_user_list()
	
	if dock:
		dock.set_ui_state(true, "Комната создана (Порт: %d)" % port)
	heartbeat_timer.start()
	log_msg("Сервер запущен на порту %d" % port)

func start_client(ip: String, port: int) -> void:
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, port)
	if err != OK:
		log_msg("Не удалось подключиться к %s:%d" % [ip, port])
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	if dock:
		dock.set_ui_state(true, "Подключение к %s..." % ip)
	heartbeat_timer.start()

func kick_player(peer_id: int) -> void:
	if not is_host or peer_id == 1:
		return
	rpc_id(peer_id, "rpc_kicked")
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
	_cleanup_peer(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func rpc_kicked() -> void:
	_terminate_session("Вы были исключены хостом")

func change_my_color(new_color: Color) -> void:
	my_custom_color = new_color
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	if connected_peers.has(my_id):
		connected_peers[my_id]["color"] = new_color
	update_ui_user_list()
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_update_peer_color", my_id, new_color)

@rpc("any_peer", "call_remote", "reliable")
func rpc_update_peer_color(peer_id: int, new_color: Color) -> void:
	if connected_peers.has(peer_id):
		connected_peers[peer_id]["color"] = new_color
	if avatars.has(peer_id) and is_instance_valid(avatars[peer_id]):
		avatars[peer_id].apply_color(new_color)
	if selection_boxes.has(peer_id) and is_instance_valid(selection_boxes[peer_id]):
		_update_box_color(selection_boxes[peer_id], new_color)
	update_ui_user_list()

func stop_session(reason: String = "Выход из сети") -> void:
	if multiplayer.has_multiplayer_peer():
		var my_name = dock.name_input.text if dock else "Dev"
		rpc("rpc_notify_disconnect", my_name)
	_terminate_session(reason)

func _terminate_session(reason: String) -> void:
	heartbeat_timer.stop()
	_clear_all_avatars()
	_clear_all_selections()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	connected_peers.clear()
	peer_last_seen.clear()
	update_ui_user_list()
	if dock:
		dock.set_ui_state(false, reason)
	log_msg("Сессия завершена: " + reason)

# --- 3D КУРСОРЫ И ВЫДЕЛЕНИЕ ---

@rpc("any_peer", "call_remote", "unreliable")
func rpc_update_cursor(peer_id: int, pos: Vector3, rot_basis: Basis) -> void:
	peer_last_seen[peer_id] = Time.get_ticks_msec() / 1000.0
	if not avatars.has(peer_id):
		_spawn_avatar(peer_id)
	if avatars.has(peer_id) and is_instance_valid(avatars[peer_id]):
		avatars[peer_id].update_transform_target(pos, rot_basis)

@rpc("any_peer", "call_remote", "reliable")
func rpc_update_selection(peer_id: int, relative_path: NodePath) -> void:
	if selection_boxes.has(peer_id) and is_instance_valid(selection_boxes[peer_id]):
		selection_boxes[peer_id].queue_free()
		selection_boxes.erase(peer_id)

	if str(relative_path) == "" or not editor_plugin:
		return

	var edited_root = editor_plugin.get_editor_interface().get_edited_scene_root()
	if not edited_root or not edited_root.has_node(relative_path):
		return

	var target_node = edited_root.get_node(relative_path)
	if target_node is Node3D:
		var p_info = connected_peers.get(peer_id, {"name": "Dev", "color": Color.WHITE})
		var box = _create_selection_box(target_node, p_info["name"], p_info["color"])
		edited_root.add_child(box)
		selection_boxes[peer_id] = box

func _create_selection_box(target: Node3D, owner_name: String, color: Color) -> Node3D:
	var root = Node3D.new()
	root.name = "__CoopSync_SelectBox"
	
	var target_global_pos = target.global_position
	var box_size = Vector3(1.5, 1.5, 1.5)
	
	if target is VisualInstance3D:
		var aabb = target.get_aabb()
		box_size = aabb.size * target.scale * 1.05
		target_global_pos = target.global_transform * (aabb.position + aabb.size * 0.5)

	root.global_position = target_global_pos

	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = box_size
	mesh_inst.mesh = box_mesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.3)
	mat.emission_enabled = true
	mat.emission = color * 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	root.add_child(mesh_inst)

	var lbl = Label3D.new()
	lbl.text = "✏️ " + owner_name
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 40
	lbl.outline_size = 10
	lbl.modulate = Color.WHITE
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.position = Vector3(0, (box_size.y * 0.5) + 0.8, 0)
	root.add_child(lbl)
	return root

func _update_box_color(box_root: Node3D, color: Color) -> void:
	for child in box_root.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			child.material_override.albedo_color = Color(color.r, color.g, color.b, 0.3)
			child.material_override.emission = color * 0.6

func _spawn_avatar(peer_id: int) -> void:
	if not editor_plugin:
		return
	var edited_root = editor_plugin.get_editor_interface().get_edited_scene_root()
	if not edited_root or not (edited_root is Node3D):
		return

	var info = connected_peers.get(peer_id, {"name": "Загрузка...", "color": Color.WHITE})
	var avatar_script = load("res://addons/coop_sync/peer_avatar.gd")
	if not avatar_script:
		return
	var avatar = avatar_script.new()
	avatar.name = "__CoopSync_Avatar_%d" % peer_id
	avatar.setup(info["name"], info.get("color", Color(0.3, 0.9, 0.3)))
	avatar.process_mode = Node.PROCESS_MODE_ALWAYS
	edited_root.add_child(avatar)
	avatars[peer_id] = avatar

func _update_existing_avatars_info() -> void:
	for p_id in avatars.keys():
		if connected_peers.has(p_id) and is_instance_valid(avatars[p_id]):
			var info = connected_peers[p_id]
			avatars[p_id].set_player_name(info.get("name", "Player"))
			avatars[p_id].apply_color(info.get("color", Color.WHITE))

func _clear_all_avatars() -> void:
	for id in avatars.keys():
		if is_instance_valid(avatars[id]):
			avatars[id].queue_free()
	avatars.clear()

func _clear_all_selections() -> void:
	for id in selection_boxes.keys():
		if is_instance_valid(selection_boxes[id]):
			selection_boxes[id].queue_free()
	selection_boxes.clear()

# --- ФАЙЛОВАЯ СИНХРОНИЗАЦИЯ ---

func sync_file(filepath: String) -> void:
	if not multiplayer.has_multiplayer_peer() or not FileAccess.file_exists(filepath):
		return
	var f = FileAccess.open(filepath, FileAccess.READ)
	var bytes = f.get_buffer(f.get_length())
	f.close()
	var sender_name = dock.name_input.text if dock else "Dev"
	rpc("rpc_receive_file", filepath, bytes, sender_name)
	log_msg("Отправлен: " + filepath.get_file())

func sync_all_project_files() -> void:
	if not multiplayer.has_multiplayer_peer():
		log_msg("Ошибка: Сначала подключитесь к комнате!")
		return
	log_msg("Синхронизация проекта...")
	_scan_and_send_dir("res://")
	log_msg("Синхронизация завершена!")

func _scan_and_send_dir(dir_path: String) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var item_name = dir.get_next()
	while item_name != "":
		if item_name.begins_with(".") or item_name == "coop_sync" or item_name.ends_with(".bak"):
			item_name = dir.get_next()
			continue
		var full_path = dir_path.path_join(item_name)
		if dir.current_is_dir():
			_scan_and_send_dir(full_path)
		else:
			var ext = item_name.get_extension().to_lower()
			if ext in ["tscn", "gd", "tres", "png", "svg", "jpg", "ttf", "otf"]:
				sync_file(full_path)
		item_name = dir.get_next()
	dir.list_dir_end()

@rpc("any_peer", "call_remote", "reliable")
func rpc_receive_file(filepath: String, file_bytes: PackedByteArray, sender: String) -> void:
	var parent_dir = filepath.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_dir):
		DirAccess.make_dir_recursive_absolute(parent_dir)

	if create_backup and FileAccess.file_exists(filepath):
		DirAccess.copy_absolute(filepath, filepath + ".bak")

	var f = FileAccess.open(filepath, FileAccess.WRITE)
	f.store_buffer(file_bytes)
	f.close()
	log_msg("Файл '%s' от %s" % [filepath.get_file(), sender])

	if editor_plugin:
		var iface = editor_plugin.get_editor_interface()
		iface.get_resource_filesystem().scan()
		var open_scenes = iface.get_open_scenes()
		if filepath in open_scenes:
			_clear_all_avatars()
			_clear_all_selections()
			iface.reload_scene_from_path(filepath)

# --- АВТОРИЗАЦИЯ, ЛОББИ И ХАРТБИТ ---

func _on_peer_connected(id: int) -> void:
	peer_last_seen[id] = Time.get_ticks_msec() / 1000.0
	if not is_host:
		var my_name = dock.name_input.text.strip_edges() if dock else "Client"
		var my_pass = dock.pass_input.text if dock else ""
		rpc_id(1, "rpc_client_handshake", my_name, my_pass, my_custom_color)

# Генерация уникального ника (если такой уже есть в лобби)
func _get_unique_peer_name(desired_name: String) -> String:
	var base_name = desired_name
	var current_name = base_name
	var counter = 1
	
	var is_taken = true
	while is_taken:
		is_taken = false
		for p_id in connected_peers.keys():
			if connected_peers[p_id].get("name", "").to_lower() == current_name.to_lower():
				is_taken = true
				current_name = "%s_%d" % [base_name, counter]
				counter += 1
				break
				
	return current_name

@rpc("any_peer", "call_remote", "reliable")
func rpc_client_handshake(client_name: String, pass_attempt: String, client_color: Color) -> void:
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var expected_pass = dock.pass_input.text if dock else ""
	if expected_pass != "" and pass_attempt != expected_pass:
		rpc_id(sender_id, "rpc_auth_result", false, "Неверный пароль!", {})
		return

	# Проверяем уникальность ника
	var final_name = _get_unique_peer_name(client_name)

	connected_peers[sender_id] = {"name": final_name, "is_host": false, "color": client_color}
	peer_last_seen[sender_id] = Time.get_ticks_msec() / 1000.0
	
	update_ui_user_list()
	_update_existing_avatars_info()
	log_msg("Разработчик '%s' вошел в лобби" % final_name)

	# Отправляем обновленный список участников
	rpc("rpc_sync_peer_list", connected_peers)
	rpc_id(sender_id, "rpc_auth_result", true, "OK", connected_peers)

@rpc("any_peer", "call_remote", "reliable")
func rpc_auth_result(ok: bool, msg: String, peers_data: Dictionary) -> void:
	if not ok:
		_terminate_session("Отказ: " + msg)
	else:
		connected_peers = peers_data
		
		# Если хост скорректировал ник, обновляем поле имени у клиента
		var my_id = multiplayer.get_unique_id()
		if connected_peers.has(my_id) and dock and dock.name_input:
			dock.name_input.text = connected_peers[my_id].get("name", dock.name_input.text)
			
		update_ui_user_list()
		_update_existing_avatars_info()
		log_msg("Успешное подключение к лобби!")

@rpc("any_peer", "call_remote", "reliable")
func rpc_sync_peer_list(peers_data: Dictionary) -> void:
	connected_peers = peers_data
	update_ui_user_list()
	_update_existing_avatars_info()

func _on_peer_disconnected(id: int) -> void:
	_cleanup_peer(id)
	if not is_host:
		_terminate_session("Связь с сервером потеряна")

func _on_server_disconnected() -> void:
	_terminate_session("Хост закрыл сессию")

func _cleanup_peer(id: int) -> void:
	if connected_peers.has(id):
		var p_name = connected_peers[id]["name"]
		connected_peers.erase(id)
		peer_last_seen.erase(id)
		if avatars.has(id) and is_instance_valid(avatars[id]):
			avatars[id].queue_free()
			avatars.erase(id)
		if selection_boxes.has(id) and is_instance_valid(selection_boxes[id]):
			selection_boxes[id].queue_free()
			selection_boxes.erase(id)
		update_ui_user_list()
		log_msg("Игрок '%s' вышел" % p_name)
		if is_host:
			rpc("rpc_sync_peer_list", connected_peers)

@rpc("any_peer", "call_remote", "unreliable")
func rpc_ping() -> void:
	var sender = multiplayer.get_remote_sender_id()
	peer_last_seen[sender] = Time.get_ticks_msec() / 1000.0
	rpc_id(sender, "rpc_pong")

@rpc("any_peer", "call_remote", "unreliable")
func rpc_pong() -> void:
	peer_last_seen[multiplayer.get_remote_sender_id()] = Time.get_ticks_msec() / 1000.0

@rpc("any_peer", "call_remote", "reliable")
func rpc_notify_disconnect(user: String) -> void:
	var sender = multiplayer.get_remote_sender_id()
	_cleanup_peer(sender)

func _on_heartbeat_tick() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	rpc("rpc_ping")
	var now = Time.get_ticks_msec() / 1000.0

	for peer_id in connected_peers.keys():
		if peer_id == multiplayer.get_unique_id():
			continue
		var last = peer_last_seen.get(peer_id, now)
		if now - last > 2.5:
			_cleanup_peer(peer_id)