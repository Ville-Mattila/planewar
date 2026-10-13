class_name ShotMain
extends Node3D
## Deterministic screenshot scene for the Xvfb + llvmpipe job (03 s14.5). Not shipped
## (export filters exclude test/**). A lit sphere ("moon") and a box ("Dart" stand-in).


func _ready() -> void:
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0.0, 1.0, 6.0)
	add_child(cam)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	add_child(light)
	var moon: MeshInstance3D = MeshInstance3D.new()
	moon.mesh = SphereMesh.new()
	var moon_mat: StandardMaterial3D = StandardMaterial3D.new()
	moon_mat.albedo_color = Color(0.7, 0.72, 0.8)
	moon.material_override = moon_mat
	moon.position = Vector3(0.0, -1.0, 0.0)
	moon.scale = Vector3(3.0, 3.0, 3.0)
	add_child(moon)
	var ship: MeshInstance3D = MeshInstance3D.new()
	ship.mesh = BoxMesh.new()
	var ship_mat: StandardMaterial3D = StandardMaterial3D.new()
	ship_mat.albedo_color = Color(0.9, 0.35, 0.1)
	ship.material_override = ship_mat
	ship.position = Vector3(1.2, 1.2, 2.0)
	ship.rotation_degrees = Vector3(20.0, 35.0, 0.0)
	add_child(ship)
