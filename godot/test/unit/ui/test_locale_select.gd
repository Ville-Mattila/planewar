extends GdUnitTestSuite
## Unit tests for ui/i18n/locale_select.gd (UX-29; docs/06 s11): selection, override and PO registration.

const TMP_SETTINGS: String = "user://test_locale_settings.cfg"

var _saved_locale: String = ""


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)
	LocaleSelect.set_pseudo(false)
	if FileAccess.file_exists(TMP_SETTINGS):
		DirAccess.remove_absolute(TMP_SETTINGS)


func test_os_language_decides_without_override() -> void:
	assert_str(LocaleSelect.resolve("fi_FI", "")).is_equal("fi")
	assert_str(LocaleSelect.resolve("fi", "auto")).is_equal("fi")
	assert_str(LocaleSelect.resolve("en_US", "auto")).is_equal("en")
	assert_str(LocaleSelect.resolve("de_DE", "")).is_equal("en")


func test_override_beats_os() -> void:
	assert_str(LocaleSelect.resolve("fi_FI", "en")).is_equal("en")
	assert_str(LocaleSelect.resolve("en_US", "FI")).is_equal("fi")
	assert_str(LocaleSelect.resolve("fi_FI", "xx")).is_equal("fi")


func test_override_persists_and_clears() -> void:
	assert_str(LocaleSelect.saved_override(TMP_SETTINGS)).is_equal("")
	assert_int(LocaleSelect.save_override(TMP_SETTINGS, "fi")).is_equal(OK)
	assert_str(LocaleSelect.saved_override(TMP_SETTINGS)).is_equal("fi")
	assert_int(LocaleSelect.save_override(TMP_SETTINGS, "auto")).is_equal(OK)
	assert_str(LocaleSelect.resolve("en_US", LocaleSelect.saved_override(TMP_SETTINGS))).is_equal("en")


func test_registered_po_translates_en_and_fi() -> void:
	assert_int(LocaleSelect.register_translations(Fmt.param_str("po_dir"))).is_equal(2)
	LocaleSelect.apply("en")
	assert_str(TranslationServer.translate(&"barks.launch.1")).is_equal("{callsign} airborne.")
	LocaleSelect.apply("fi")
	assert_str(TranslationServer.translate(&"barks.launch.1")).is_equal("{callsign} ilmassa.")


func test_untranslated_finnish_falls_back_to_english() -> void:
	var _n: int = LocaleSelect.register_translations(Fmt.param_str("po_dir"))
	LocaleSelect.apply("fi")
	# hud.speed has no Finnish row yet (UX-30): the English string, never the key.
	assert_str(TranslationServer.translate(&"hud.speed")).is_equal("SPD")


func test_pseudo_flag_round_trips() -> void:
	LocaleSelect.set_pseudo(true)
	assert_bool(TranslationServer.pseudolocalization_enabled).is_true()
	LocaleSelect.set_pseudo(false)
	assert_bool(TranslationServer.pseudolocalization_enabled).is_false()
