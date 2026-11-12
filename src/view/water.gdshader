shader_type canvas_item;
render_mode blend_mix;

// Procedural river water for Commander In Chief (view-only, deterministic-safe).
//
// Each visible water band is a ColorRect quad (main.gd _sync_water) sized WATER_H
// tall PLUS pad_px of dry-side padding on each edge, spanning the screen width,
// sitting at z=-1 (under the immediate-mode units, over the z=-2 grass background).
// This shader paints murky blue-green water with scrolling value-noise ripples, an
// animated sun-glint specular band, a shallow->deep depth gradient that follows a
// wobbling (non-ruler-straight) shoreline, foam that hugs that shoreline, and a
// translucent near-bank ramp so the riverbed shows through. It fades to transparent
// across the dry ford (the sand ford strip is drawn on top in main.gd, over the
// grass gap).
//
// SAFETY: no screen/depth reads, only stock canvas_item ops + fixed loops, so it
// compiles and renders identically on gl_compatibility (screenshot/movie backend)
// and Forward+ (Metal). Self-contained: procedural noise, no external texture.

uniform vec2 rect_size = vec2(640.0, 108.0);          // padded band pixel size (aspect fix)
uniform float pad_px = 14.0;                          // dry-side padding baked into the quad, each edge
uniform float band_px = 80.0;                         // true sim band height in px (unpadded)
uniform vec2 bank_amp = vec2(5.0, 2.5);                // px of shore displacement per harmonic
uniform vec2 bank_freq = vec2(6.5, 15.0);              // radians across the 640px screen width (matches main.gd BANK_FREQ; always pushed, these are just the idle defaults)
uniform float ford_center = 0.5;                      // ford center, in UV.x (0..1)
uniform float ford_halfw = 0.05;                      // ford half-width, in UV.x
// Which way the river runs, from SimWorld.ford_flow_dir(band): -1 / 0 / +1. The
// streaks below were hardcoded drifting +x while _ford_current shoves you the other
// way on half the reachable bands. 0 (band 1, which has no current) draws no streaks
// at all rather than inventing a direction the sim does not have.
uniform float flow_dir = 1.0;
uniform vec4 shallow_col : source_color = vec4(0.21, 0.44, 0.47, 1.0);
uniform vec4 deep_col : source_color = vec4(0.08, 0.19, 0.31, 1.0);
uniform float speed : hint_range(0.0, 2.0) = 0.32;
uniform float phase = 0.0;   // per-band time offset so two visible bands never ripple in lockstep
// View clock — NOT GPU TIME. main.gd advances this only when hit-stop is off
// and scales it by Reduce Motion, so a freeze-frame river stays frozen.
uniform float clock = 0.0;
// One expanding splash ring (wet explosion): center in band-relative UV (0..1
// across the true water band, NOT the padded quad), t 1→0 as it spreads.
uniform vec2 splash_uv = vec2(-10.0, 0.5);
uniform float splash_t = 0.0;
// Bow wakes: up to two units standing in the water. xy = band-relative UV
// (matches splash_uv), z = strength (0 = inactive).
uniform vec3 wake0 = vec3(-10.0, 0.5, 0.0);
uniform vec3 wake1 = vec3(-10.0, 0.5, 0.0);
// Washed-out ford: while the sim floods the crossing (surge = 1) the shader paints
// churning white water over ford_halfw's worth of UV either side of ford_center, with
// feathered, noise-broken edges (no rectangle). surge_halfw is the REAL crossing half
// width; ford_halfw is pushed negative while closed, so it cannot carry it.
uniform float surge = 0.0;
uniform float surge_halfw = 0.05;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);   // smooth interpolation
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

// Bow wake: expanding concentric ripple rings that fade as they travel out, a tight
// foam collar hugging the wader, and a lacy V wash trailing downstream (+y in band
// space). uv_band is (screen-x-fraction, band-relative-y-fraction); the x term is
// rescaled by rect_size.x/band_px so rings read round against the wide, short band.
// Returns (foam, shade): foam is added bright, shade darkens the water between rings.
vec2 wake(vec3 w, vec2 uv_band, float ck) {
	if (w.z < 0.001) {
		return vec2(0.0);
	}
	vec2 wd = (uv_band - w.xy) * vec2(rect_size.x / band_px, 1.0);
	float r = length(wd);
	float foam = smoothstep(0.045, 0.008, abs(r - 0.14)) * 0.9;
	float shade = 0.0;
	for (int k = 0; k < 3; k++) {
		float ph = fract(ck * 0.55 + float(k) / 3.0);
		float rr = 0.15 + ph * 0.30;
		float fade = (1.0 - ph) * smoothstep(0.0, 0.12, ph);
		float ring = smoothstep(0.028, 0.0, abs(r - rr));
		foam += ring * fade * 0.55;
		shade += smoothstep(0.05, 0.0, abs(r - rr - 0.035)) * fade * 0.35;
	}
	float lace = 0.55 + 0.45 * vnoise(vec2(wd.x * 22.0, wd.y * 22.0 - ck * 2.0));
	float arm = smoothstep(0.06, 0.0, abs(abs(wd.x) * 0.7 - (wd.y + 0.02)));
	float v = arm * step(0.0, wd.y) * smoothstep(0.34, 0.0, wd.y) * lace;
	foam += v * 0.55;
	return vec2(foam * w.z, shade * w.z);
}

void fragment() {
	vec2 uv = UV;
	// Aspect-correct sample coords (~36px per noise cell) so ripples read square
	// on the wide, short band instead of horizontally smeared.
	vec2 p = uv * (rect_size / 36.0);
	float t = (clock + phase) * speed;

	// Two layers drifting in different directions -> a churning surface.
	float n1 = fbm(p + vec2(t * 1.3, t * 0.6));
	float n2 = fbm(p * 1.7 + vec2(-t * 0.8, t * 1.1) + 11.3);
	float ripple = n1 * 0.65 + n2 * 0.35;

	// Map the padded quad back to band space: b = 0 at the sim's top waterline,
	// 1 at its bottom waterline. Anything outside [0,1] is dry-side padding.
	float total = band_px + pad_px * 2.0;
	float b = (uv.y * total - pad_px) / band_px;
	float u = uv.x;

	// Organic shoreline (the tell this whole pass exists to kill): displace each
	// bank with two out-of-phase sines — the SAME curve main.gd's sand polygon
	// draws, driven by the same per-band `phase` uniform — plus a high-frequency
	// noise jitter so the edge wobbles like a real one instead of a ruler line.
	// jit() is WaterPolish.bank_jitter in GDScript, term for term: the sand polygon is
	// drawn from it so the water edge and the sand edge are the same irregular line.
	float top_off = (bank_amp.x * sin(u * bank_freq.x + phase)
	               + bank_amp.y * sin(u * bank_freq.y + phase * 1.7)
	               + 1.1 * sin(u * 41.0 + phase * 3.1) + 0.6 * sin(u * 63.0 + phase * 5.3)) / band_px;
	float bot_off = (bank_amp.x * sin(u * bank_freq.x + phase + 2.1)
	               + bank_amp.y * sin(u * bank_freq.y + (phase + 2.1) * 1.7)
	               + 1.1 * sin(u * 41.0 + (phase + 2.1) * 3.1) + 0.6 * sin(u * 63.0 + (phase + 2.1) * 5.3)) / band_px;
	float d_top = b - top_off;                      // >0 = inside the water (past the top shore)
	float d_bot = (1.0 - bot_off) - b;              // >0 = inside the water (before the bottom shore)
	float d = min(d_top, d_bot);                    // band-fraction distance to the nearer shore

	// Depth: a smooth shelf from the banks down to a dark mid-channel, with slow
	// lateral "pools" so the deep run meanders instead of sitting in a stripe. Shallows
	// pick up a silty olive tint, the way a real river clears from bank to channel.
	float dpx = d * band_px;
	float pool = vnoise(vec2(u * 3.2 + phase, 0.7)) - 0.5;
	float depth = smoothstep(0.0, 1.0, clamp((dpx + pool * 10.0) / 30.0, 0.0, 1.0));
	float lit = clamp((1.0 - depth) * 0.85 + (ripple - 0.5) * 0.30, 0.0, 1.0);
	vec3 col = mix(deep_col.rgb, shallow_col.rgb, lit);
	col = mix(col, shallow_col.rgb * vec3(1.12, 1.06, 0.80), pow(1.0 - depth, 2.5) * 0.45);

	// Crest the noise into brighter wave fronts so the surface reads as moving
	// water even in a still frame (units draw strictly on top, so this is free).
	float crest = smoothstep(0.52, 0.78, ripple);
	col += vec3(0.07, 0.12, 0.13) * crest * (0.6 + 0.9 * depth);
	// Downstream current: long noise filaments aligned with the flow, drifting the way
	// the sim's own ford current shoves you (dark troughs + pale crests), so direction
	// reads in a still frame. One token flips both space and time.
	float fd = flow_dir;
	vec2 fp = vec2((p.x * 0.75 - t * 2.4) * fd, p.y * 5.0);
	float fl = vnoise(fp) * 0.65 + vnoise(fp * vec2(2.3, 1.7) + 5.1) * 0.35;
	float fmask = abs(sign(fd));
	col += vec3(0.16, 0.21, 0.21) * smoothstep(0.70, 0.92, fl) * 0.22 * fmask;
	col *= 1.0 - 0.12 * smoothstep(0.38, 0.12, fl) * fmask;
	// Fine wavelets: thin warped crest lines running across the channel, brighter
	// toward the middle, so the surface reads as water at native 640x360.
	float wv = sin((uv.x * rect_size.x * 0.11 + ripple * 5.0 - t * 5.0 * fd) + uv.y * 9.0);
	col += vec3(0.05, 0.09, 0.10) * smoothstep(0.82, 1.0, wv) * (0.3 + 0.7 * depth);
	col *= 1.0 - 0.07 * smoothstep(-0.2, -1.0, wv) * depth;

	// Sun glints: a soft drifting specular band broken by the ripples, plus crisp
	// two-pixel twinkles that flick on and off on the wave crests only.
	float glintband = 0.5 + 0.5 * sin(uv.x * 3.2 + uv.y * 6.0 - (clock + phase) * 1.4);
	float glint = smoothstep(0.70, 1.0, glintband * (0.55 + 0.5 * ripple));
	col += vec3(0.50, 0.58, 0.50) * glint * 0.22;
	vec2 cell = floor(uv * rect_size / 2.0);
	float tw = hash(cell + floor((clock + phase) * 2.5) * 7.0);
	float spark = step(0.982, tw) * step(0.58, ripple) * smoothstep(0.1, 0.4, depth * 0.6 + 0.4);
	col = mix(col, vec3(0.93, 0.97, 0.88), spark * 0.85);

	// Shoreline foam: irregular, lacy and broken instead of a clean stripe. Width
	// breathes along the bank, a lace mask punches holes, and a second sparse line of
	// foam flecks rides a few pixels off the bank. Gated 1px onto the dry side so a
	// missing bank polygon can never expose a pale halo across the whole pad.
	float breathe = vnoise(vec2(u * 11.0 + phase, t * 0.30));
	float foam_w = (3.0 + 4.5 * breathe) / band_px;
	float lace = vnoise(vec2(u * 46.0, dpx * 0.45 - t * 1.1 * max(fmask, 0.25)));
	float foam_gate = step(-1.0 / band_px, d);
	float foam = smoothstep(foam_w, 0.0, d) * foam_gate * smoothstep(0.18, 0.55, lace + 0.35 * (1.0 - d / foam_w));
	float fleck = smoothstep(0.80, 0.93, vnoise(vec2(u * 38.0 + t * 0.4, dpx * 0.35))) *
		smoothstep(2.0, 5.0, dpx) * smoothstep(13.0, 7.0, dpx) * (0.5 + 0.5 * breathe);
	col = mix(col, vec3(0.88, 0.92, 0.89), clamp(foam * 0.85 + fleck * 0.45, 0.0, 1.0));
	// Darker, cooler water just off the foam sells the depth step at the bank.
	col *= 1.0 - 0.10 * smoothstep(12.0, 5.0, dpx) * smoothstep(1.0, 4.0, dpx);

	// Wet-blast splash ring + bow wakes: both keyed off band-relative (u, b) so they
	// stay correctly placed regardless of the dry-side padding.
	if (splash_t > 0.001) {
		vec2 sd = (vec2(u, b) - splash_uv) * vec2(rect_size.x / band_px, 1.0);
		float sring = smoothstep(0.14, 0.02, abs(length(sd) - (1.0 - splash_t) * 1.5)) * splash_t;
		col += vec3(0.55, 0.60, 0.58) * sring;
	}
	float ck = clock + phase;
	vec2 wk0 = wake(wake0, vec2(u, b), ck);
	vec2 wk1 = wake(wake1, vec2(u, b), ck);
	col *= 1.0 - 0.18 * clamp(wk0.y + wk1.y, 0.0, 1.0);
	col = mix(col, vec3(0.86, 0.92, 0.89), clamp(wk0.x + wk1.x, 0.0, 1.0) * 0.55);

	// Dry ford: fade the water to transparent across the crossing so the sand
	// strip (drawn over the grass gap in main.gd) reads as a dry path; a jittered
	// margin gives a shallow, muddy, non-ruler edge on each side.
	float df = abs(u - ford_center) + (fbm(vec2(b * 6.0, t * 0.2)) - 0.5) * 0.012;
	float ford_alpha = smoothstep(ford_halfw, ford_halfw + 0.03, df);

	// Flooded crossing: white water churning over the (washed-out) ford span, broken
	// at the edges by noise and streaming with the current, never a ruled box.
	if (surge > 0.5) {
		float sdx = abs(u - ford_center);
		float edge = (vnoise(vec2(b * 9.0, t * 0.5 + 3.0)) - 0.5) * 0.02;
		float sm = smoothstep(surge_halfw + 0.012, surge_halfw - 0.02, sdx + edge);
		vec2 sp = vec2(p.x * 2.4 - t * 3.2 * fd, p.y * 15.0);
		float sw = vnoise(sp) * 0.6 + vnoise(sp * 2.3 + 7.0) * 0.4;
		float churn = smoothstep(0.55, 0.85, sw) * sm;
		col = mix(col, col * 0.78 + vec3(0.03, 0.05, 0.05), sm * 0.55);
		col = mix(col, vec3(0.86, 0.91, 0.88), churn * 0.5);
	}

	// Shore translucency: near the (curved) bank the ground beneath shows through —
	// that IS the visible riverbed. Foam licks a few px onto the dry sand too.
	float shore = smoothstep(0.0, 7.0 / band_px, d);
	float alpha = shore * mix(0.55, 1.0, smoothstep(0.0, 22.0 / band_px, d));
	alpha = max(alpha, foam);
	alpha *= ford_alpha;

	COLOR = vec4(col, alpha);
}
