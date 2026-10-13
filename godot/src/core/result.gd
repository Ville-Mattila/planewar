class_name Result extends RefCounted
## ok/err value without exceptions.

var ok: bool = false
var error: int = 0
var message: String = ""
var value: Variant = null


static func success(v: Variant = null) -> Result:
	var r: Result = Result.new()
	r.ok = true
	r.value = v
	return r


static func failure(code: int, msg: String) -> Result:
	var r: Result = Result.new()
	r.ok = false
	r.error = code
	r.message = msg
	return r
