@tool
extends EditorPlugin

const SERVER_URL = "http://127.0.0.1:8000/get_pending_commands?engine=godot"
const POLL_INTERVAL = 1.5  # segundos

var poll_timer: Timer
var current_request: HTTPRequest = null

func _enter_tree():
	poll_timer = Timer.new()
	poll_timer.wait_time = POLL_INTERVAL
	poll_timer.autostart = true
	poll_timer.timeout.connect(_poll_server)
	add_child(poll_timer)
	print("[HUNNIGAN] Plugin activado, escuchando en ", SERVER_URL)

func _exit_tree():
	if poll_timer:
		poll_timer.queue_free()
	if current_request:
		current_request.queue_free()

func _poll_server():
	if current_request and current_request.get_http_client_status() == HTTPClient.STATUS_REQUESTING:
		return
	if current_request:
		current_request.queue_free()
	current_request = HTTPRequest.new()
	add_child(current_request)
	current_request.request_completed.connect(_on_commands_received)
	var error = current_request.request(SERVER_URL)
	if error != OK:
		print("[HUNNIGAN] Error al solicitar comandos: ", error)
		current_request.queue_free()
		current_request = null

func _on_commands_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	current_request.queue_free()
	current_request = null
	
	if response_code != 200:
		print("[HUNNIGAN] Respuesta HTTP no exitosa: ", response_code)
		return
	
	var body_str = body.get_string_from_utf8()
	if body_str.is_empty() or body_str == "[]":
		return
	
	var json = JSON.new()
	var parse_error = json.parse(body_str)
	if parse_error != OK:
		print("[HUNNIGAN] Error parseando JSON: ", json.get_error_message())
		return
	
	var commands = json.data
	if not commands is Array:
		print("[HUNNIGAN] Formato de respuesta inválido (no es array)")
		return
	
	for cmd in commands:
		_execute_command(cmd)

func _execute_command(cmd: Dictionary):
	var action = cmd.get("action", "SPAWN")
	match action:
		"SPAWN":
			_spawn_asset(cmd)
		"WRITE_CODE":
			_write_script(cmd)
		"DELETE":
			_delete_asset(cmd)
		_:
			print("[HUNNIGAN] Acción desconocida: ", action)

func _spawn_asset(cmd: Dictionary):
	var editor_root = get_editor_interface().get_edited_scene_root()
	if not editor_root:
		print("[HUNNIGAN] No hay escena abierta, no se puede instanciar.")
		return
	
	var asset = cmd.get("asset_data", {})
	var name = asset.get("name", "NodoHunnigan")
	var type_3d = asset.get("type", "3D") == "3D"
	
	var node: Node
	if type_3d:
		node = _create_primitive_3d(name)
	else:
		node = Node2D.new()
		node.name = name
	
	if not node:
		print("[HUNNIGAN] No se pudo crear el nodo para: ", name)
		return
	
	# Aplicar transformación
	var tx = cmd.get("transform", {})
	var pos = tx.get("position", {})
	var rot = tx.get("rotation", {})
	var scl = tx.get("scale", {})
	if type_3d:
		node.position = Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0))
		node.rotation = Vector3(rot.get("x", 0.0), rot.get("y", 0.0), rot.get("z", 0.0))
		node.scale = Vector3(scl.get("x", 1.0), scl.get("y", 1.0), scl.get("z", 1.0))
	else:
		node.position = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
		node.rotation = rot.get("z", 0.0)
		node.scale = Vector2(scl.get("x", 1.0), scl.get("y", 1.0))
	
	# Scripting
	var scripting = cmd.get("scripting", {})
	var script_content = scripting.get("content", "").strip_edges()
	if not script_content.is_empty():
		var script_file_name = scripting.get("file_name", name)
		var script_path = "res://scripts/%s.gd" % script_file_name
		_save_script_file(script_path, script_content)
		var script_res = load(script_path)
		if script_res:
			node.set_script(script_res)
		else:
			print("[HUNNIGAN] No se pudo cargar el script: ", script_path)
	
	editor_root.add_child(node)
	node.owner = editor_root
	print("[HUNNIGAN] Instanciado: ", node.name, " en la escena actual")

# Función corregida: ya no usa el operador 'in', sino 'contains()'
func _create_primitive_3d(name: String) -> MeshInstance3D:
	var lower = name.to_lower()
	var mesh: PrimitiveMesh = null
	
	if lower.contains("cubo") or lower.contains("cube") or lower.contains("caja") or lower.contains("box"):
		mesh = BoxMesh.new()
	elif lower.contains("esfera") or lower.contains("sphere") or lower.contains("bola"):
		mesh = SphereMesh.new()
	elif lower.contains("cilindro") or lower.contains("cylinder") or lower.contains("columna"):
		mesh = CylinderMesh.new()
	elif lower.contains("capsula") or lower.contains("capsule"):
		mesh = CapsuleMesh.new()
	else:
		mesh = BoxMesh.new()  # por defecto
	
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = name
	return mi

func _write_script(cmd: Dictionary):
	var scripting = cmd.get("scripting", {})
	var file_name = scripting.get("file_name", "unnamed_script")
	var content = scripting.get("content", "")
	if content.is_empty():
		print("[HUNNIGAN] Script vacío, no se guarda.")
		return
	var path = "res://scripts/%s.gd" % file_name
	_save_script_file(path, content)
	print("[HUNNIGAN] Script guardado: ", path)

func _save_script_file(path: String, content: String):
	var dir = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		get_editor_interface().get_resource_filesystem().scan()
	else:
		print("[HUNNIGAN] Error guardando script en: ", path)

func _delete_asset(cmd: Dictionary):
	print("[HUNNIGAN] Acción DELETE no implementada aún")
