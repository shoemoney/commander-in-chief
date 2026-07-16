shader_type canvas_item;

// Full-screen "concussion" post-process (view-only). When the player is downed,
// main.gd ramps `concussion` (0..1) and the world briefly goes underwater:
// a gentle radial blur toward screen center, mild chromatic aberration, a slow
// wobble, a touch of desaturation, and a dark vignette pulse — disorienting,
// not a seizure. Works on both Forward+ (Metal) and gl_compatibility (the
// screenshot/movie tooling) using only stock canvas_item screen-reading.
//
// SAFETY: at concussion <= 0 this is a bit-exact pass-through. main.gd also
// hides the ColorRect entirely when not concussed, so normal play never even
// triggers the backbuffer copy — this early-out is the belt to that suspenders.

// filter_linear (not _mipmap): every sample here is a plain texture() on a
// full-screen quad at ~1:1 UV, so LOD always lands on mip 0 — the _mipmap hint
// just forced a full backbuffer mip chain to be generated every visible frame.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float concussion : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// NOTE: Godot forbids `return` inside fragment() — the identity path is the
	// `if` branch, the effect the `else`. Both assign COLOR, so at concussion<=0
	// this is a bit-exact pass-through.
	if (concussion < 0.001) {
		COLOR = texture(screen_tex, SCREEN_UV);
	} else {
		float amt = clamp(concussion, 0.0, 1.0);
		vec2 uv = SCREEN_UV;
		vec2 to_center = vec2(0.5) - uv;   // inward; length ~0 center .. ~0.707 corner
		float dist = length(to_center);

		// Slow underwater wobble on the sample UV, scaled by concussion.
		float wob = sin(TIME * 2.3 + uv.y * 12.0) + cos(TIME * 1.7 + uv.x * 10.0);
		vec2 wob_uv = uv + vec2(wob) * 0.0022 * amt;

		// Radial blur: a few taps marching toward screen center.
		vec3 blur = texture(screen_tex, wob_uv).rgb;
		for (int i = 1; i < 4; i++) {
			vec2 s = wob_uv + to_center * (float(i) * 0.018 * amt);
			blur += texture(screen_tex, s).rgb;
		}
		blur *= 0.25;

		// Chromatic aberration: split R/B along the radial axis.
		vec2 ca = normalize(to_center + vec2(1e-5)) * (0.0045 * amt);
		vec3 col = vec3(
			texture(screen_tex, wob_uv + ca).r,
			blur.g,
			texture(screen_tex, wob_uv - ca).b
		);
		col = mix(col, blur, 0.5);   // fold the soft blur back into all channels

		// Mild desaturation.
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(luma), 0.35);

		// Subtle dark vignette with a slow pulse.
		float vig = 1.0 - smoothstep(0.3, 0.75, dist);   // 1 center -> 0 edge
		float pulse = 0.9 + 0.1 * sin(TIME * 3.0);
		col *= mix(1.0, vig * pulse, 0.55);

		// Master blend: whole effect intensity rides `concussion`, so it eases in
		// and out (a second pass-through guarantee as amt -> 0).
		vec3 clean = texture(screen_tex, SCREEN_UV).rgb;
		COLOR = vec4(mix(clean, col, amt), 1.0);
	}
}
