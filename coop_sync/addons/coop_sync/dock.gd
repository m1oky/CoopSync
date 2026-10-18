@tool
extends VBoxContainer

var editor_plugin: EditorPlugin
var net: Node

var name_input: LineEdit
var ip_input: LineEdit
var port_input: SpinBox
var pass_input: LineEdit
var host_btn: Button
var join_btn: Button
var disconnect_btn: Button
var sync_all_btn: Button
var auto_sync_check: CheckBox
var backup_check: CheckBox
var status_lbl: Label
var users_count_lbl: Label
var users_list: ItemList
var log_box: TextEdit

var context_menu: PopupMenu
var palette_window: Window
var selected_item_peer_id: int = -1

# 10 готовых ярких цветов
const PRESET_COLORS = [
	Color(0.2, 0.75, 1.0),  # Неоновый Синий
	Color(0.2, 0.9, 0.35),  # Сочный Лайм
	Color(1.0, 0.25, 0.25), # Рубиновый Красный
	Color(1.0, 0.85, 0.15), # Солнечный Желтый
	Color(0.75, 0.3, 1.0),  # Фиолетовый
	Color(0.05, 0.95, 0.85),# Морской Циан
	Color(1.0, 0.45, 0.1),  # Оранжевый
	Color(1.0, 0.4, 0.75),  # Розовый
	Color(0.1, 0.8, 0.55),  # Изумрудный
	Color(0.95, 0.95, 0.95) # Белый
]

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var title = Label.new()
	title.text = "CoopSync v1.2"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	add_child(HSeparator.new())

	name_input = LineEdit.new()
	name_input.placeholder_text = "Имя"
	name_input.text = "m1oky"
	add_child(name_input)

	ip_input = LineEdit.new()
	ip_input.placeholder_text = "IP хоста"
	ip_input.text = "127.0.0.1"
	add_child(ip_input)

	port_input = SpinBox.new()
	port_input.min_value = 1024
	port_input.max_value = 65535
	port_input.value = 7777
	port_input.prefix = "Порт: "
	add_child(port_input)

	pass_input = LineEdit.new()
	pass_input.placeholder_text = "Пароль комнаты (если нужен)"
	pass_input.secret = true
	add_child(pass_input)

	var act_box = HBoxContainer.new()
	host_btn = Button.new()
	host_btn.text = "Создать"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(func(): if net: net.start_host(int(port_input.value)))

	join_btn = Button.new()
	join_btn.text = "Войти"
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(func(): if net: net.start_client(ip_input.text.strip_edges(), int(port_input.value)))

	disconnect_btn = Button.new()
	disconnect_btn.text = "Выйти"
	disconnect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disconnect_btn.disabled = true
	disconnect_btn.pressed.connect(func(): if net: net.stop_session("Отключено пользователем"))

	act_box.add_child(host_btn)
	act_box.add_child(join_btn)
	act_box.add_child(disconnect_btn)
	add_child(act_box)

	sync_all_btn = Button.new()
	sync_all_btn.text = "🔄 Синхронизировать весь проект"
	sync_all_btn.disabled = true
	sync_all_btn.pressed.connect(func(): if net: net.sync_all_project_files())
	add_child(sync_all_btn)

	add_child(HSeparator.new())

	auto_sync_check = CheckBox.new()
	auto_sync_check.text = "Авто-синхронизация при Ctrl+S"
	auto_sync_check.button_pressed = true
	auto_sync_check.toggled.connect(func(v): if net: net.auto_sync_enabled = v)
	add_child(auto_sync_check)

	backup_check = CheckBox.new()
	backup_check.text = "Создавать копии .bak"
	backup_check.button_pressed = true
	backup_check.toggled.connect(func(v): if net: net.create_backup = v)
	add_child(backup_check)

	status_lbl = Label.new()
	status_lbl.text = "Статус: Не в сети"
	add_child(status_lbl)

	add_child(HSeparator.new())

	# Список лобби
	users_count_lbl = Label.new()
	users_count_lbl.text = "👥 В лобби (0):"
	add_child(users_count_lbl)

	users_list = ItemList.new()
	users_list.custom_minimum_size = Vector2(0, 95)
	users_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	users_list.item_clicked.connect(_on_user_item_clicked)
	add_child(users_list)

	log_box = TextEdit.new()
	log_box.custom_minimum_size = Vector2(0, 100)
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.editable = false
	log_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(log_box)

	_setup_context_menu()
	_setup_palette_dialog()

func _setup_context_menu() -> void:
	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(context_menu)

func _setup_palette_dialog() -> void:
	palette_window = Window.new()
	palette_window.title = "Выбор цвета (10 вариантов)"
	palette_window.size = Vector2i(270, 140)
	palette_window.visible = false
	palette_window.close_requested.connect(func(): palette_window.hide())

	var grid = GridContainer.new()
	grid.columns = 5
	grid.position = Vector2(10, 10)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)

	for col in PRESET_COLORS:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(42, 42)
		var sb = StyleBoxFlat.new()
		sb.bg_color = col
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		
		var captured_col = col
		btn.pressed.connect(func():
			if net:
				net.change_my_color(captured_col)
			palette_window.hide()
		)
		grid.add_child(btn)

	palette_window.add_child(grid)
	add_child(palette_window)

func _on_user_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	
	selected_item_peer_id = int(users_list.get_item_metadata(index))
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var is_me = (selected_item_peer_id == my_id)
	var am_i_host = net.is_host if net else false

	context_menu.clear()
	if is_me:
		context_menu.add_item("🎨 Выбрать цвет", 1)
	elif am_i_host:
		context_menu.add_item("❌ Выгнать из сессии", 2)
	
	if context_menu.item_count > 0:
		context_menu.position = DisplayServer.mouse_get_position()
		context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	if id == 1:
		palette_window.popup_centered()
	elif id == 2:
		if net and selected_item_peer_id > 0:
			net.kick_player(selected_item_peer_id)

func log_msg(text: String) -> void:
	var time_str = Time.get_time_string_from_system()
	if log_box:
		log_box.text += "[%s] %s\n" % [time_str, text]
		log_box.scroll_vertical = log_box.get_line_count()

func set_ui_state(active: bool, msg: String) -> void:
	status_lbl.text = "Статус: " + msg
	host_btn.disabled = active
	join_btn.disabled = active
	disconnect_btn.disabled = !active
	sync_all_btn.disabled = !active
	name_input.editable = !active
	ip_input.editable = !active
	port_input.editable = !active
	pass_input.editable = !active

func refresh_users(peers: Dictionary) -> void:
	if not users_list:
		return
	users_list.clear()
	users_count_lbl.text = "👥 В лобби (%d):" % peers.size()
	
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	
	for peer_id in peers.keys():
		var info = peers[peer_id]
		var label_str = info.get("name", "Unknown")
		
		# Хост — это тот, у кого peer_id == 1 или флаг is_host
		var peer_is_host = info.get("is_host", false) or (peer_id == 1)
		if peer_is_host:
			label_str += " [Хост]"
		if peer_id == my_id:
			label_str += " (Вы)"
		
		var idx = users_list.add_item(label_str)
		var user_col = info.get("color", Color.WHITE)
		users_list.set_item_custom_fg_color(idx, user_col)
		users_list.set_item_metadata(idx, peer_id)