class_name SkyShot
extends Node3D
## ART-15 sky golden (07 s1.5, R0 C2-31): the moon sky alone, no terrain. Not shipped (export filters exclude test/**).
## User args after `--`:  --view=earth|sun|stars|wide   --plain (ocean only)   --sun=<deg about +Y>   --frames=N   --shot=<png>
##   earth  camera on -Z, fov 12: prints SKY_EARTH (disc diameter in degrees, offset of its centroid from -Z, mean ocean colour)
##   sun    camera on sun_dir, fov 12: prints SKY_SUN (disc diameter, centre colour)
##   stars  camera on +Y, fov 60: prints SKY_STARS (background byte vs #05070C, star pixel count, brightest pixel)
##   wide   camera 19 degrees above the Earth direction, fov 80: picture only
## Colour measured as the final framebuffer byte (sRGB), the same convention as lookdev_shot.

const SPACE_HEX: String = "#05070C"
const OCEAN_HEX: String = "#3F6FB5"

var cam: Camera3D
var _view: String = "earth"
var _frames: int = 6
var _shot: String = ""
var _frame: int = 0
var _sun: Vector3 = MoonLight.DEFAULT_SUN_DIR
var _plain: bool = false


func _ready() -> void:
	var sun_deg: float = 0.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			_view = arg.substr(7)
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
		elif arg.begins_with("--shot="):
			_shot = arg.substr(7)
		elif arg == "--plain":
			_plain = true
		elif arg.begins_with("--sun="):
			sun_deg = float(arg.substr(6))
	MoonLight.ensure_globals()
	_sun = MoonLight.DEFAULT_SUN_DIR.rotated(Vector3.UP, deg_to_rad(sun_deg))
	MoonLight.set_sun_dir(_sun)
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = MoonLight.make_environment()
	SkyMoon.apply(we.environment)
	(we.environment.sky.sky_material as ShaderMaterial).set_shader_parameter(&"earth_plain", 1.0 if _plain else 0.0)
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 12.0
	add_child(cam)
	var look: Vector3 = SkyMoon.earth_dir()
	match _view:
		"sun":
			look = _sun
		"stars":
			look = Vector3.UP
			cam.fov = 60.0
		"wide":
			look = Vector3(0.0, 0.35, -1.0).normalized()   # Earth 19 degrees below the frame centre, stars above
			cam.fov = 80.0
	cam.look_at(cam.global_position + look, Vector3.UP if absf(look.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	cam.make_current()


func _process(_delta: float) -> void:
	_frame += 1
	if _frame >= _frames:
		_finish()


func _finish() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		match _view:
			"earth":
				_report_disc(img, "SKY_EARTH", 0.20, true)
			"sun":
				_report_disc(img, "SKY_SUN", 1.5, false)
			"stars":
				_report_stars(img)
		if not _shot.is_empty():
			var _e: Error = img.save_png(_shot)
	print("SKY view=%s adapter=%s driver=%s" % [_view, RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name()])
	get_tree().quit(0)


func _px_per_deg(img: Image) -> float:
	return float(img.get_height()) * 0.5 / tan(deg_to_rad(cam.fov * 0.5)) * PI / 180.0


## Disc = pixels whose channel sum exceeds `min_sum` (the 12 degree frame holds only the disc and flat space).
func _report_disc(img: Image, tag: String, min_sum: float, with_colour: bool) -> void:
	var cx: int = img.get_width() >> 1
	var cy: int = img.get_height() >> 1
	var n: int = 0
	var sum: Vector2 = Vector2.ZERO
	var ocean: Vector3 = Vector3.ZERO
	var n_ocean: int = 0
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.r + c.g + c.b > min_sum:
				n += 1
				sum += Vector2(x, y)
				if with_colour and c.b > c.r * 1.25 and c.b > 0.45 and c.g < c.b * 0.9:
					ocean += Vector3(c.r, c.g, c.b)
					n_ocean += 1
	if n == 0:
		print("%s none" % tag)
		return
	var centroid: Vector2 = sum / float(n)
	var ppd: float = _px_per_deg(img)
	var diameter: float = 2.0 * sqrt(float(n) / PI) / ppd
	var offset: float = (centroid - Vector2(cx, cy)).length() / ppd
	var mid: Color = img.get_pixel(cx, cy)
	var line: String = "%s diameter_deg=%.2f offset_deg=%.3f centre8=(%d,%d,%d)" % [tag, diameter, offset, mid.r8, mid.g8, mid.b8]
	if with_colour and n_ocean > 0:
		var m: Vector3 = ocean / float(n_ocean)
		var got: Color = Color(m.x, m.y, m.z)
		line += " ocean_mean=#%s ocean_target=%s" % [got.to_html(false), OCEAN_HEX]
	print(line)


func _report_stars(img: Image) -> void:
	var space: Color = Color(SPACE_HEX)
	var stars: int = 0
	var bright: float = 0.0
	var bg: Color = img.get_pixel(3, 3)
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			var l: float = c.r + c.g + c.b
			if l > 0.25:
				stars += 1
			bright = maxf(bright, l / 3.0)
	print("SKY_STARS background8=(%d,%d,%d) space8=(%d,%d,%d) star_pixels=%d brightest=%.2f" % [
		bg.r8, bg.g8, bg.b8, space.r8, space.g8, space.b8, stars, bright])
