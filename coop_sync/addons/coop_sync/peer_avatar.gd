@tool
extends Node3D

var target_position: Vector3 = Vector3.ZERO
var target_basis: Basis = Basis.IDENTITY

var sphere_mesh: MeshInstance3D
var pointer_mesh: MeshInstance3D
var name_label: Label3D
var cur_color: Color = Color.WHITE

func setup(player_name: String, color: Color) -> void:
	cur_color = color

	sphere_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	sphere_mesh.mesh = sphere
	add_child(sphere_mesh)

	pointer_mesh = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.25
	cone.height = 0.85
	pointer_mesh.mesh = cone
	pointer_mesh.transform = Transform3D().rotated(Vector3.RIGHT, -PI * 0.5).translated(Vector3(0, 0, -0.65))
	add_child(pointer_mesh)

	name_label = Label3D.new()
	name_label.text = player_name
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.font_size = 38
	name_label.outline_size = 8
	name_label.position = Vector3(0, 0.9, 0)
	add_child(name_label)

	apply_color(color)

func apply_color(color: Color) -> void:
	cur_color = color
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.6)
	mat.emission_enabled = true
	mat.emission = color * 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	sphere_mesh.material_override = mat
	pointer_mesh.material_override = mat
	if name_label:
		name_label.modulate = color

func set_player_name(new_name: String) -> void:
	if name_label:
		name_label.text = new_name

func _process(delta: float) -> void:
	# Моментальная сверхплавная доводка
	var t = clamp(delta * 55.0, 0.0, 1.0)
	global_position = global_position.lerp(target_position, t)
	
	var cur_quat = global_transform.basis.get_rotation_quaternion()
	var tgt_quat = target_basis.get_rotation_quaternion()
	global_transform.basis = Basis(cur_quat.slerp(tgt_quat, t))

func update_transform_target(pos: Vector3, rot_basis: Basis) -> void:
	target_position = pos
	target_basis = rot_basis