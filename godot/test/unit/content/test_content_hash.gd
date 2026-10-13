extends GdUnitTestSuite
## N1: the GDScript canonicaliser reproduces tools/content_hash.py byte for byte.



func _vector() -> Dictionary:
	var path: String = ProjectSettings.globalize_path("res://").path_join("../tools/tests/content_hash_vector.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(parsed is Dictionary).is_true()
	var d: Dictionary = parsed
	return d


func test_vector_inclusion_order_and_canonical_strings() -> void:
	var v: Dictionary = _vector()
	var files: Dictionary = v["files"]
	var included: PackedStringArray = ContentHash.included_names(files.keys())
	var expected: Array = v["included"]
	assert_int(included.size()).is_equal(expected.size())
	var canon: Array = v["canonical"]
	for i: int in included.size():
		assert_str(included[i]).is_equal(str(expected[i]))
		var parsed: Variant = JSON.parse_string(str(files[included[i]]))
		assert_str(ContentHash.canonical(parsed)).is_equal(str(canon[i]))


func test_vector_sha256_matches_python_value() -> void:
	var v: Dictionary = _vector()
	var h: PackedByteArray = ContentHash.hash_texts(v["files"])
	assert_int(h.size()).is_equal(32)
	assert_str(h.hex_encode()).is_equal(str(v["sha256"]))


func test_number_text_rules() -> void:
	assert_str(ContentHash.number_text(300.0)).is_equal("300")
	assert_str(ContentHash.number_text(-0.0)).is_equal("0")
	assert_str(ContentHash.number_text(0.1)).is_equal("0.1")
	assert_str(ContentHash.number_text(0.00001)).is_equal("0.00001")
	assert_str(ContentHash.number_text(1234.5)).is_equal("1234.5")
	assert_str(ContentHash.number_text(-2.5)).is_equal("-2.5")
	assert_str(ContentHash.number_text(0.1 + 0.2)).is_equal("0.30000000000000004")
	assert_str(ContentHash.number_text(1.0e-7)).is_equal("0.0000001")
	assert_str(ContentHash.number_text(123456.789012)).is_equal("123456.789012")
	assert_str(ContentHash.number_text(4503599627370496.0)).is_equal("4503599627370496")
	assert_str(ContentHash.number_text(9007199254740992.0)).is_equal("")
	assert_str(ContentHash.number_text(INF)).is_equal("")
	assert_str(ContentHash.number_text(NAN)).is_equal("")


func test_strings_escape_only_the_required_characters() -> void:
	assert_str(ContentHash.canonical("a\"b\\c\nd\u0001eä")).is_equal("\"a\\\"b\\\\c\\nd\\u0001eä\"")
	assert_str(ContentHash.canonical({"b": 1, "a": [true, false, null], "_doc": "x", "presentation": {}})) \
		.is_equal("{\"a\":[true,false,null],\"b\":1}")


func test_excluded_files_do_not_change_the_hash() -> void:
	var base: Dictionary = {"a.json": "{\"x\":1}"}
	var with_extra: Dictionary = {"a.json": "{\"x\":1}", "sfx.json": "{\"y\":2}", "chat_filter.json": "[]",
		"vfx_prewarm.json": "{}", "notes.txt": "hi"}
	assert_str(ContentHash.hash_texts(base).hex_encode()).is_equal(ContentHash.hash_texts(with_extra).hex_encode())
	var changed: Dictionary = {"a.json": "{\"x\":2}"}
	assert_str(ContentHash.hash_texts(base).hex_encode()).is_not_equal(ContentHash.hash_texts(changed).hex_encode())


func test_comments_and_presentation_changes_do_not_change_the_hash() -> void:
	var a: Dictionary = {"a.json": "{\"x\":1,\"_doc\":\"one\",\"p\":{\"presentation\":{\"mesh\":\"m\"}}}"}
	var b: Dictionary = {"a.json": "{ \"p\":{\"presentation\":{\"mesh\":\"other\"}}, \"x\": 1.0, \"_doc\": \"two\" }"}
	assert_str(ContentHash.hash_texts(a).hex_encode()).is_equal(ContentHash.hash_texts(b).hex_encode())


func test_unparsable_file_gives_empty_hash() -> void:
	assert_int(ContentHash.hash_texts({"a.json": "{ nope"}).size()).is_equal(0)


func test_content_db_hash_is_stable_32_bytes_and_equals_python_on_real_defs() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	assert_int(ContentDB.content_hash().size()).is_equal(32)
	assert_int(ContentDB.content_hash_hex().length()).is_equal(64)
	var first: String = ContentDB.content_hash_hex()
	var r2: Result = ContentDB.load_all()
	assert_bool(r2.ok).is_true()
	assert_str(ContentDB.content_hash_hex()).is_equal(first)
	var root: String = ProjectSettings.globalize_path("res://").path_join("../")
	var out: Array = []
	var code: int = OS.execute("python", ["-I", "-c",
		"import sys;sys.path.insert(0,sys.argv[1]);import content_hash as c;from pathlib import Path;print(c.content_hash(Path(sys.argv[2])))",
		root + "tools", root + "godot/content/defs"], out)
	if code != 0:
		return  # no python on this machine; CI has it
	assert_str(str(out[0]).strip_edges()).is_equal(first)
