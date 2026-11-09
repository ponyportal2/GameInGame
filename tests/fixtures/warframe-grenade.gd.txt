extends Node3D
# Live-injected grenade mechanic.
# Middle mouse button throws a grenade from the camera toward the aim
# direction. It explodes on impact/fuse/enemy proximity, using the game's
# own _explode_at() so damage falloff, FX and sound match the base game.

const COOLDOWN := 0.7
const SPEED := 34.0
const LIFT := 3.5
const GRAVITY := 22.0
const FUSE := 1.7
const RADIUS := 8.0
const DAMAGE := 650.0
const TRAIL_STEP := 0.035

var _cd := 0.0
var _grenades : Array = []


func _init() -> void:
	pass


func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)


func _input(ev : InputEvent) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_MIDDLE:
		return
	var game := get_parent()
	if game == null or String(game.get("mode")) != "playing":
		return
	throw_grenade()


func throw_grenade() -> void:
	if _cd > 0.0:
		return
	_cd = COOLDOWN
	var game := get_parent()
	if game == null:
		return
	var origin : Vector3 = Vector3(0.0, 1.6, 0.0)
	var dir : Vector3 = Vector3(0.0, 0.0, -1.0)
	var cam = game.get("cam")
	if cam != null and is_instance_valid(cam):
		origin = cam.global_position
		var bz : Vector3 = cam.global_transform.basis.z
		if bz.length() > 0.001:
			dir = -bz.normalized()
	else:
		var ppos = game.get("pos")
		if ppos != null:
			origin = Vector3(ppos) + Vector3(0.0, 1.6, 0.0)
	var vel : Vector3 = dir * SPEED + Vector3(0.0, LIFT, 0.0)

	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.82, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.4)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = origin
	add_child(mi)

	var li := OmniLight3D.new()
	li.light_color = Color(0.35, 1.0, 0.45)
	li.light_energy = 6.0
	li.omni_range = 7.0
	mi.add_child(li)

	_grenades.append({"mesh": mi, "pos": origin, "vel": vel, "t": 0.0, "trail": 0.0})


func _process(delta : float) -> void:
	if _cd > 0.0:
		_cd = maxf(0.0, _cd - delta)
	if _grenades.is_empty():
		return
	var game := get_parent()
	var keep : Array = []
	for g in _grenades:
		var gd : Dictionary = g
		var t : float = float(gd["t"]) + delta
		gd["t"] = t
		var vel : Vector3 = gd["vel"]
		vel.y -= GRAVITY * delta
		var p : Vector3 = gd["pos"] + vel * delta
		gd["vel"] = vel
		gd["pos"] = p
		var mesh = gd["mesh"]
		if mesh != null and is_instance_valid(mesh):
			mesh.position = p
			mesh.rotate_y(delta * 9.0)

		var tl : float = float(gd["trail"]) + delta
		if tl >= TRAIL_STEP and game != null and game.get("fx") != null:
			tl = 0.0
			game.fx.spawn(p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.3, 0.06,
					Color(0.32, 1.0, 0.42), -1.0, 2.0, 1.0)
		gd["trail"] = tl

		var boom := false
		var at : Vector3 = p
		if p.y <= 0.25:
			boom = true
			at = Vector3(p.x, 0.2, p.z)
		elif t >= FUSE:
			boom = true
		elif game != null:
			var ens = game.get("enemies")
			if ens != null:
				for e in ens:
					var ed : Dictionary = e
					if bool(ed["dead"]):
						continue
					var ev3 : Vector3 = ed["pos"] + Vector3(0.0, float(ed["h"]) * 0.5, 0.0)
					if p.distance_to(ev3) <= float(ed["r"]) + 0.7:
						boom = true
						break

		if boom:
			if mesh != null and is_instance_valid(mesh):
				mesh.queue_free()
			if game != null:
				game._explode_at(at, RADIUS, DAMAGE, -1)
		else:
			keep.append(gd)
	_grenades = keep
