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
// Same contract as water.gdshader: GPU TIME kept wobbling through hit-stop.
uniform float clock = 0.0;
// FOCUS — screen UV of the thing the warp must leave legible: the soldier whose
// ears are ringing. main.gd pushes it from the SHIPPED world->screen seam
// (main._concussion_focus_uv -> _to_screen). Default vec2(0.5) only so a bare
// material (editor preview, a caller that forgets) degrades to screen centre.
uniform vec2 focus = vec2(0.5);
// SPARE — how much of the peripheral ramp to apply, because this shader has TWO
// consumers with opposite intents. 1.0 = the concussion channel: open the warp up
// around `focus`. 0.0 = the blast heat-shock (_blast_warp, marquee kills): a flat
// whole-frame punch, bit-for-bit the pre-ramp behaviour, because a detonation
// should hit HARDEST where it went off. main.gd crossfades on which is louder.
// Default 0.0 keeps an un-set material on the old, unshaped path.
uniform float spare : hint_range(0.0, 1.0) = 0.0;

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
		// Distance from the FOCUS, not from the middle of the frame. This game has
		// no horizontal camera — main._to_screen() is `(round(fx * PX),
		// round((fy - camera_top) * PX))`, no x term — so the soldier's world x IS
		// his screen x across the 16..624 play field and he is routinely 200+ px
		// off centre. A ramp anchored at vec2(0.5) spares a fixed disc of SCREEN,
		// which is a different fix and not the one that was wanted.
		float dist = length(focus - uv);
		// PERIPHERAL RAMP. The radial blur taps below were already distance-scaled
		// by construction (they march along `to_center`, so they are 0 px at the
		// exact screen centre) — but the wobble, the chroma split and the blur fold
		// were not, and they were the loud ones: a constant whole-image shove, a
		// constant R/B split that normalize() had stripped `dist` back out of, and
		// a flat 50% fold. Net effect, the fallen soldier — the one thing the
		// player is squinting at to find out whether he got back up — came out
		// doubled and smeared. Everything that DISPLACES a sample now rides this.
		//
		// MEASURED by tools/probe_concussion_hud.gd at the shipped SOLO-knockdown
		// peak 1.0 (down_self_scale(false) — 0.7 is the lesser vest-break beat).
		// Exposure-matched strong-edge retention in the box around the LIVE soldier,
		// swept across the play field. Shipped column is the median of 3 runs on
		// Apple M4 Max / OpenGL 4.1 Metal; the two control columns reproduce to
		// within a hundredth run-to-run, the shipped one does NOT — it spreads
		// ~0.98..1.12, so quote the median, not a bare triple:
		//         no ramp   ramp @ vec2(0.5)   ramp @ focus
		//   x=40    0.00          0.01             1.01
		//   x=320   0.09          0.98             1.07
		//   x=600   0.00          0.04             1.03
		// Across all 9 shipped-column samples the worst single sample 0.98, which
		// is the number CENTRE_KEEP_RATIO's 0.85 floor actually has to clear.
		// The middle column is what anchoring at screen centre buys: the soldier is
		// legible only on the rare frames where he happens to stand in the middle.
		//
		// This REDISTRIBUTES the warp, it does not weaken it — "the periphery is
		// untouched" would be false. Gradient-sum retention (|dI/dx| summed,
		// concussed vs clean) by region, screen-centred ramp -> focus ramp, with the
		// soldier at x=40: left edge (x 0-80) 0.40 -> 0.67 and the far right edge
		// 0.39 -> 0.28; at x=600 the mirror, right edge 0.37 -> 0.62 and left edge
		// 0.42 -> 0.31. The top strip (y 60-110) drops 0.64 -> 0.32 at every pose,
		// because the focus rides low on screen (the soldier stands at y~300) and the
		// top of the frame is now genuinely far from it. LUMA is byte-comparable
		// everywhere before and after (left edge 53.46 vs 53.39, top strip 62.69 vs
		// 62.69 of 255) — the vignette grade below is untouched by any of this.
		float ramp = smoothstep(0.3, 0.75, dist);   // 0 at the focus -> 1 far from it
		// `spare` picks which consumer's intent applies — see the uniform above.
		float periph = mix(1.0, ramp, spare);

		// Slow underwater wobble on the sample UV, scaled by concussion.
		float wob = sin(clock * 2.3 + uv.y * 12.0) + cos(clock * 1.7 + uv.x * 10.0);
		vec2 wob_uv = uv + vec2(wob) * 0.0022 * amt * periph;

		// Radial blur: a few taps marching toward screen center.
		vec3 blur = texture(screen_tex, wob_uv).rgb;
		for (int i = 1; i < 4; i++) {
			vec2 s = wob_uv + to_center * (float(i) * 0.018 * amt);
			blur += texture(screen_tex, s).rgb;
		}
		blur *= 0.25;

		// Chromatic aberration: split R/B along the radial axis.
		vec2 ca = normalize(to_center + vec2(1e-5)) * (0.0045 * amt * periph);
		// Green is the blur's own channel, so it needs the same ramp as the fold
		// below — otherwise the taps' vertical reach lands on the soldier at full
		// strength no matter what the other two channels do, and the "spared
		// centre" is only spared in R and B.
		vec3 col = vec3(
			texture(screen_tex, wob_uv + ca).r,
			mix(texture(screen_tex, wob_uv).g, blur.g, periph),
			texture(screen_tex, wob_uv - ca).b
		);
		col = mix(col, blur, 0.5 * periph);   // fold the soft blur back into all channels

		// Mild desaturation.
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(luma), 0.35);

		// Subtle dark vignette with a slow pulse. DELIBERATELY screen-centred, and
		// deliberately NOT the complement of `periph` above: the ramp now moves with
		// the soldier, and a vignette that followed him would read as a dark blob
		// wandering around the frame. Same falloff constants, different anchor —
		// the warp is aimed at the player, the darkening frames the screen.
		float vig = 1.0 - smoothstep(0.3, 0.75, length(to_center));   // 1 center -> 0 edge
		float pulse = 0.9 + 0.1 * sin(clock * 3.0);
		col *= mix(1.0, vig * pulse, 0.55);

		// Master blend: whole effect intensity rides `concussion`, so it eases in
		// and out (a second pass-through guarantee as amt -> 0).
		vec3 clean = texture(screen_tex, SCREEN_UV).rgb;
		COLOR = vec4(mix(clean, col, amt), 1.0);
	}
}
