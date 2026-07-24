shader_type canvas_item;

// a4-01 MASTER COLOR GRADE — the game's one unifying "film". The world had no
// tonemap/LUT (the only full-screen pass was the black-alpha CRT scanline/vignette),
// so each biome read as its own hue-island. This is an always-on, deliberately SUBTLE
// post that samples the finished frame (world + HUD, below this on the fx layer) and
// grades it so every screen shares one print — WITHOUT flattening the biome hue
// contrast the a1..a3 palette work built. Works on Forward+ (Metal) and
// gl_compatibility (the screenshot/movie backend) via stock screen reading.
//
// A `grade` uniform (0..1) master-scales the whole effect; `breather` folds in the
// a4-15 shop/intermission calm variant (gentle exposure lift + extra desaturation).
//
// This is the TOP of the unification stack, not the whole of it: the per-sprite
// TINT/OUTLINE tables in src/view/art.gd already pull the 4 asset sources (legacy art
// bakes, Kenney tiles, authored soldier PNGs, generated boss/vehicle art) onto one
// palette family BEFORE this pass ever runs (warm-bright threats, olive/gunmetal
// vehicles, receding mossy decor, one shared Art.PRINT_INK dark rim/backing). This
// shader is the final full-frame "print" laid over that already-graded source art.
// See assets_src/style_bible.md for the full family writeup + swatch values.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float grade : hint_range(0.0, 1.0) = 1.0;
uniform float breather : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));

	// (1) Gentle filmic highlight shoulder — soft-clips the white-hot cores so they
	// roll off instead of flat-clipping, and lifts midtones a hair. Mixed lightly.
	vec3 shoulder = c / (c + vec3(0.22)) * 1.22;
	vec3 g = mix(c, shoulder, 0.30);

	// (2) A whisper of shared warmth lifted into the SHADOWS only (amber in the darks),
	// so the whole game feels lit by one warm key — strongest where luma is low.
	g += vec3(0.030, 0.014, -0.010) * (1.0 - luma);

	// (3) ~6% global desaturation toward luma — pulls the hue-islands a touch closer
	// to one film. Small on purpose: biome hue contrast must survive.
	g = mix(g, vec3(luma), 0.06);

	// Master scale (grade=0 -> untouched original).
	c = mix(c, g, grade);

	// (4) Shop/intermission breather (a4-15's leftover visual half): a calm exposure
	// lift + a cooler extra desaturation so "you're safe to buy" reads as a breath.
	if (breather > 0.001) {
		float bl = dot(c, vec3(0.299, 0.587, 0.114));
		vec3 calm = mix(c, vec3(bl), 0.12) * 1.05 + vec3(-0.008, 0.0, 0.016);
		c = mix(c, calm, breather);
	}

	COLOR = vec4(c, 1.0);
}
