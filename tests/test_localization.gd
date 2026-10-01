extends RefCounted
## localization-text-pipeline: the pipeline itself (project.godot registration + the
## English-string-as-key TranslationServer.translate() contract used by Menu.setting_help,
## hud.gd's caption strip, main.gd's _hint() choke point, hud.gd's verb-legend words, and
## menu.gd's shared nav-legend choke point) plus a CJK-specific layout-overflow regression
## guard for HudIcons._wrap_caption. Every test that sets TranslationServer's global locale
## restores it (and removes the translations it added) unconditionally before returning --
## a leaked non-"en" locale would silently translate every English-literal wording assertion
## in every OTHER suite sharing this one SceneTree process.

const Runner := preload("res://tests/run_tests.gd")
const Hud := preload("res://src/view/hud.gd")
const MainScript := preload("res://src/main.gd")


func _reset_locale(added: Array) -> void:
	for tr in added:
		TranslationServer.remove_translation(tr)
	TranslationServer.set_locale("en")


func test_locale_translations_registered_in_project_settings() -> void:
	var paths: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	Runner.T.ok(paths.size() >= 3, "project.godot registers at least 3 locale/translations entries")
	for code in ["es", "fr", "ja"]:
		var expect := "res://locale/strings.%s.po" % code
		Runner.T.ok(paths.has(expect), "locale/translations lists %s" % expect)
	Runner.T.eq(ProjectSettings.get_setting("internationalization/locale/fallback", ""), "en",
		"the project falls back to English when a translation is missing")


# Every .po the project ships must actually load as a Translation resource and resolve at
# least one real UI key -- catches a typo'd msgid, a bad encoding, or a path drift between
# project.godot and the file on disk before it ever reaches a player.
func test_each_shipped_po_loads_and_translates_a_known_key() -> void:
	var en_sfx_help := "SFX: LOUDNESS OF WEAPON, HIT, AND EXPLOSION SOUNDS. SAVED AUTOMATICALLY."
	for code in ["es", "fr", "ja"]:
		var tr := load("res://locale/strings.%s.po" % code)
		Runner.T.ok(tr != null, "locale/strings.%s.po loads as a resource" % code)
		TranslationServer.add_translation(tr)
		TranslationServer.set_locale(code)
		var got := GameMenu.setting_help("sfx")
		Runner.T.ok(got != "" and got != en_sfx_help,
			"%s translates the SFX setting-help line away from the English source" % code)
		# An id with no SETTING_HELP entry still safely returns "" (unknown-key contract) --
		# translate() is never handed an empty source string.
		Runner.T.eq(GameMenu.setting_help("no_such_setting"), "", "%s: unmapped id still returns \"\"" % code)
		self._reset_locale([tr])
		Runner.T.eq(TranslationServer.translate(en_sfx_help), en_sfx_help,
			"%s: resetting the locale restores the untranslated English fallback" % code)


# AUD#4's caption strip wraps on spaces (txt.split(" ")) -- fine for English/es/fr, but
# Japanese/Chinese have NO spaces at all, so a translated VO caption arrives as ONE
# unbreakable "word". Before the CJK fallback, that meant a translated caption long enough
# to exceed CAPTION_MAX_W just overflowed the strip uncontested. This pins the fix: any
# space-less string, however long, still comes back as lines that each fit the box, with
# every character preserved in order.
func test_cjk_caption_wrap_never_overflows_caption_max_w() -> void:
	var font := Art.font()
	# Space-less by construction (Japanese punctuation only) and, at Hud.FONT_SIZE, wider
	# than Hud.CAPTION_MAX_W -- exercises the character-fallback path the word-only wrap
	# used to skip entirely.
	var long_ja := "スポッター：「戦費がゼロになった、蘇生はもうできない、これが最後の抵抗だ、絶対に諦めるな、最後まで撃ち続けて敵を全滅させろ、援軍は来ない、諦めるな！」"
	var full_w: float = font.get_string_size(long_ja, HORIZONTAL_ALIGNMENT_LEFT, -1, Hud.FONT_SIZE).x
	Runner.T.ok(full_w > Hud.CAPTION_MAX_W, "fixture string is wide enough to force a wrap (sanity check on the fixture itself)")
	var lines := Hud._wrap_caption(long_ja, font, Hud.FONT_SIZE, Hud.CAPTION_MAX_W)
	Runner.T.ok(lines.size() > 1, "an oversized space-less CJK line still wraps onto more than one line")
	for ln in lines:
		var w: float = font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, Hud.FONT_SIZE).x
		Runner.T.ok(w <= Hud.CAPTION_MAX_W + 0.5, "CJK wrapped line '%s' fits within CAPTION_MAX_W" % ln)
	Runner.T.eq("".join(lines), long_ja, "character-level wrap drops or reorders no glyph")
	# A short CJK line (no space to trigger the fallback, and already under budget) is
	# untouched -- proves the fallback only engages when the plain word-wrap would overflow.
	var short_ja := "スポッター：「敵観測兵発見！」"
	var short_lines := Hud._wrap_caption(short_ja, font, Hud.FONT_SIZE, Hud.CAPTION_MAX_W)
	Runner.T.eq(short_lines.size(), 1, "a short CJK caption stays a single line")
	Runner.T.eq(short_lines[0], short_ja, "a short CJK caption is returned verbatim")


# HOW TO PLAY's large-text pager uses its own locale-safe wrapper because its
# instructional copy is much wider and more varied than the caption strip. A
# deliberately extreme no-space translation proves the longest corpus cannot be
# hard-clipped: every character survives, in order, at the requested 200% size.
func test_howto_large_text_wrap_preserves_extreme_localized_corpus() -> void:
	var source := "ACCESSIBILITY LONG-CORPUS FIXTURE"
	var translated := "大型文字対応確認文章".repeat(36)
	var tr := Translation.new()
	tr.locale = "ja"
	tr.add_message(source, translated)
	TranslationServer.add_translation(tr)
	TranslationServer.set_locale("ja")
	var size := 22   # the manual's 11px body at 200%
	var lines := GameMenu.howto_wrap_lines(source, size, GameMenu.BODY_W)
	Runner.T.ok(lines.size() > 2, "the extreme Japanese fixture reflows across many manual lines")
	for line in lines:
		var w := Art.font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		Runner.T.ok(w <= GameMenu.BODY_W + 0.5, "large-text localized line fits the manual content well")
	Runner.T.eq("".join(lines), translated, "large-text wrapping drops, clips, or reorders no localized character")
	self._reset_locale([tr])


# main.gd's _hint() choke point, exercised through the REAL method (not a re-implementation
# of the translate() call) -- MainScript.new() alone is safe headless (same pattern as
# test_leaderboard.gd's _StubMainGate: field initializers run, _ready() never fires since
# the instance is never add_child'd). _menu defaults to GameMenu.Mode.HIDDEN (not TITLE),
# so _hint() runs its normal body instead of early-returning.
func test_hint_choke_point_translates_a_static_literal_before_queueing() -> void:
	var en := "ARMORED — WAIT FOR THE CORE"
	var tr := load("res://locale/strings.fr.po")
	TranslationServer.add_translation(tr)
	TranslationServer.set_locale("fr")
	var stub := MainScript.new()
	stub._menu.mode = GameMenu.Mode.HIDDEN   # _menu defaults to Mode.TITLE, where _hint() early-returns
	stub._hint("armor_test_only", en)
	Runner.T.eq(stub._hint_queue.size(), 1, "_hint() queues exactly one toast for a first-time id")
	var queued: String = stub._hint_queue[0]
	Runner.T.ok(queued != en and queued != "", "fr: the queued hint text is translated, not the raw English literal")
	# Calling again with the SAME id must stay silent (first-time-only contract) -- proves the
	# translate() call didn't disturb the _seen dedup that gates it.
	stub._hint("armor_test_only", en)
	Runner.T.eq(stub._hint_queue.size(), 1, "a repeat _hint() call for an already-seen id queues nothing more")
	stub.free()
	self._reset_locale([tr])


# The five _hint() templates that interpolate a device glyph/ransom number BEFORE the call
# (claymore/revive/pilot/supply/airstrike_wheel) translate their OWN template first, so the
# runtime substitution still lands in the translated sentence, not just the English one.
func test_templated_hint_translates_and_still_formats_the_placeholder() -> void:
	var tr := load("res://locale/strings.es.po")
	TranslationServer.add_translation(tr)
	TranslationServer.set_locale("es")
	var got: String = TranslationServer.translate("HOLD [%s] FOR THE SUPPLY WHEEL") % "Q"
	Runner.T.ok(got.contains("Q"), "es: the %s glyph placeholder survives translate()+format")
	Runner.T.ok(not got.contains("HOLD"), "es: the template itself is translated, not left in English")
	var ransom: String = TranslationServer.translate("RESCUE THE DOWNED PILOT — TOUCH HIM, AIM AWAY — %d¢ RANSOM") % 250
	Runner.T.ok(ransom.contains("250"), "es: the %d ransom amount survives translate()+format")
	self._reset_locale([tr])


# hud.gd's verb-legend chip (ROLL / SUPPLY WHEEL / REVIVE) translates its 3 words at the
# SAME choke point (VERB_SEGS) both verb_legend_extent measures and verb_legend_primitives
# draws from -- so the two never disagree on width even under a locale that renders wider.
func test_verb_legend_words_translate_consistently_between_measure_and_draw() -> void:
	var tr := load("res://locale/strings.ja.po")
	TranslationServer.add_translation(tr)
	TranslationServer.set_locale("ja")
	var prims := Hud.verb_legend_primitives(100.0)
	Runner.T.eq(prims.size(), Hud.VERB_SEGS.size(), "verb_legend_primitives emits one entry per VERB_SEGS word")
	for i in prims.size():
		var en: String = Hud.VERB_SEGS[i][1]
		Runner.T.ok(prims[i]["label_txt"] != en, "ja: verb-legend word '%s' is translated" % en)
		var measured: float = Art.font().get_string_size(prims[i]["label_txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		Runner.T.ok(absf(prims[i]["label"].size.x - measured) < 0.5,
			"ja: the drawn label rect width matches a fresh measure of the SAME translated text")
	self._reset_locale([tr])


# menu.gd's shared SELECT/BACK nav-legend choke point (legend_extent/legend_primitives/
# _legend_row all read GameMenu._legend_label) -- covers every footer/nav strip across
# PAUSE/OPTS/SETUP/HALL/HOWTO in one place, without touching the dozens of call sites that
# build {"label": "SELECT"/"BACK"} dict literals.
func test_nav_legend_select_and_back_translate_through_shared_choke_point() -> void:
	var tr := load("res://locale/strings.fr.po")
	TranslationServer.add_translation(tr)
	TranslationServer.set_locale("fr")
	var select_seg := {"label": "SELECT"}
	var back_seg := {"label": "BACK"}
	var select_fr := GameMenu._legend_label(select_seg)
	var back_fr := GameMenu._legend_label(back_seg)
	Runner.T.ok(select_fr != "SELECT", "fr: SELECT translates via the shared legend choke point")
	Runner.T.ok(back_fr != "BACK", "fr: BACK translates via the shared legend choke point")
	# legend_extent must measure the TRANSLATED text, not the English source -- a glyph-less
	# single-segment row's extent formula reduces to exactly the label's measured width, so
	# this proves legend_extent reads the SAME translated string _legend_label just returned
	# (not a stale English one that would silently overrun the layout the extent guarantees).
	var f := Art.font()
	var expect_w: float = f.get_string_size(select_fr, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var got_w: float = GameMenu.legend_extent([select_seg])[1]
	Runner.T.ok(absf(got_w - expect_w) < 0.5, "fr: legend_extent measures the translated SELECT label, not the English source")
	self._reset_locale([tr])


# The shipped project font must actually carry CJK glyphs, or every Japanese string above
# is silently rendering as tofu/empty boxes -- a missing glyph measures at (or very near)
# 0px advance width, so a real per-CHARACTER width across a spread of common kanji/kana/
# punctuation is the cheapest headless proof the font has real coverage (a screenshot
# harness would be the only way to SEE tofu; this at least catches "no glyph at all").
func test_shipped_font_has_real_cjk_glyph_coverage() -> void:
	var font := Art.font()
	var sample := "戦費観測兵指揮官蘇生装甲補給ホイール、。！「」"
	for i in sample.length():
		var ch := sample.substr(i, 1)
		var w: float = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, Hud.FONT_SIZE).x
		Runner.T.ok(w > 1.0, "font renders a real (non-tofu) glyph for CJK character '%s' (advance=%.2f)" % [ch, w])


## Every character the view can DRAW must exist in the shipped font — because a
## character it does NOT have is not a tofu box, it is a SYSTEM FONT FALLBACK, and
## a fallback measures differently on every platform.
##
## How this shipped: the K.I.A. card drew "...WAR CHEST BANKED  → +1,234" and
## PixelOperator8.ttf has no U+2192. Nothing errored. The card simply measured wider
## on Windows, where the 13-row maximum produced 20 row-vs-row overlaps against the
## 12 ratcheted on macOS — and windows CI went red on a layout test that had never
## been given a reason. The GATE SECURED banner's "⚡FAST" (U+26A1, also absent) was
## worse: banner_fit_size steps the font size down until the string fits, so the
## fallback's extra width silently rendered that banner at a different point size
## per platform. Both now use U+00BB, which the face does carry.
##
## THE INSTRUMENT IS has_char, NOT get_string_size — and that is the whole point.
## The CJK test above measures a width, which a fallback supplies perfectly well, so
## it cannot see this class of bug at all. has_char asks the font what it actually
## has. (Corollary, and the reason this is worth stating: a gate built on the wrong
## instrument is not a weak gate, it is a gate that reports the opposite of the
## truth.)
##
## SCOPE: every non-ASCII character in src/ with line comments stripped. Comments
## are excluded because nobody draws them, and a `→` in a comment is documentation,
## not a defect — including the ones in this file. Non-ASCII is the whole risk
## surface: ASCII is present in any font that renders English, and GDScript
## identifiers cannot be non-ASCII, so what survives comment-stripping is drawn
## text, a label, or a glyph constant.
func test_no_drawn_character_falls_back_to_a_system_font() -> void:
	var font := Art.font()
	# --- CONTROLS. A gate that cannot fail is not a gate, and an empty sweep is a
	# BLIND gate — both are checked here so neither can ship wearing a pass.
	Runner.T.ok(not font.has_char(0x2192),
		"CONTROL: the shipped font genuinely lacks U+2192 '→', so this census CAN report a fallback")
	Runner.T.ok(font.has_char(0x00BB),
		"CONTROL: the substitute U+00BB '»' is present, so the fix is not trading one fallback for another")
	var scanned_files := 0
	var scanned_chars := 0
	var missing: Array[String] = []
	var seen: Dictionary = {}
	var dir := DirAccess.open("res://src")
	Runner.T.ok(dir != null, "src/ is readable for the drawn-glyph census")
	if dir == null:
		return
	for f in _gd_files(dir):
		scanned_files += 1
		for line in FileAccess.get_file_as_string("res://src/" + f).split("\n"):
			var code := _strip_line_comment(line)
			for i in code.length():
				var cp := code.unicode_at(i)
				# ASCII is present in any font that renders English; GDScript
				# identifiers cannot be non-ASCII. Only the rest can fall back.
				if cp < 0xA0:
					continue
				scanned_chars += 1
				if font.has_char(cp):
					continue
				var key := "U+%04X" % cp
				if seen.has(key):
					continue
				seen[key] = true
				missing.append("%s (%s) — first at src/%s" % [key, _chr(cp), f])
	Runner.T.ok(scanned_files >= 8,
		"the census walked the view source, not two files (%d .gd under src/)" % scanned_files)
	Runner.T.ok(scanned_chars > 20,
		"the census actually examined non-ASCII characters (%d) — an empty sweep would pass vacuously"
			% scanned_chars)
	Runner.T.eq(missing.size(), 0,
		"every non-ASCII character in src/ (comments stripped) exists in the shipped font, so no drawn string can fall back to a platform-dependent system font%s"
			% ["" if missing.is_empty() else " — missing: " + ", ".join(missing)])


## Every .gd path under `dir`, recursively, as posix-ish relative paths.
func _gd_files(dir: DirAccess) -> Array[String]:
	var out: Array[String] = []
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append(name)
	for sub in dir.get_directories():
		var d2 := DirAccess.open("res://src/" + sub)
		if d2 == null:
			continue
		for f in _gd_files(d2):
			out.append(sub + "/" + f)
	return out


## The line with its `#` comment removed, respecting string literals so a `#`
## inside "..." is not mistaken for the start of a comment. Unterminated quotes
## are treated as running to end of line, which is the safe direction: it can only
## over-report, and over-reporting here means a suspicious char gets looked at.
func _strip_line_comment(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			out += c
			if c == "\\" and i + 1 < line.length():
				out += line[i + 1]
				i += 2
				continue
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
			out += c
		elif c == "#":
			break
		else:
			out += c
		i += 1
	return out


static func _chr(cp: int) -> String:
	return String.chr(cp)
