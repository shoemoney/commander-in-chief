shader_type canvas_item;
render_mode blend_mix;

// Procedural river water for Project Ikari (view-only, deterministic-safe).
//
// Each visible water band is a ColorRect quad (main.gd _sync_water) sized WATER_H
// tall, spanning the screen width, sitting at z=-1 (under the immediate-mode units,
// over the z=-2 grass background). This shader paints murky blue-green water with
// scrolling value-noise ripples, an animated sun-glint specular band, a subtle
// shallow->deep depth gradient, and shore foam. It fades to transparent across the
// dry ford (the sand ford strip is drawn on top in main.gd, over the grass gap).
//
// SAFETY: no screen/depth reads, only stock canvas_item ops + fixed loops, so it
// compiles and renders identically on gl_compatibility (screenshot/movie backend)
// and Forward+ (Metal). Self-contained: procedural noise, no external texture.

uniform vec2 rect_size = vec2(640.0, 80.0);           // band pixel size (aspect fix)
uniform float ford_center = 0.5;                      // ford center, in UV.x (0..1)
uniform float ford_halfw = 0.05;                      // ford half-width, in UV.x
uniform vec4 shallow_col : source_color = vec4(0.21, 0.44, 0.47, 1.0);
uniform vec4 deep_col : source_color = vec4(0.08, 0.19, 0.31, 1.0);
uniform float speed : hint_range(0.0, 2.0) = 0.32;

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

void fragment() {
	vec2 uv = UV;
	// Aspect-correct sample coords (~36px per noise cell) so ripples read square
	// on the wide, short band instead of horizontally smeared.
	vec2 p = uv * (rect_size / 36.0);
	float t = TIME * speed;

	// Two layers drifting in different directions -> a churning surface.
	float n1 = fbm(p + vec2(t * 1.3, t * 0.6));
	float n2 = fbm(p * 1.7 + vec2(-t * 0.8, t * 1.1) + 11.3);
	float ripple = n1 * 0.65 + n2 * 0.35;

	// Depth: lighter/shallower toward both banks, deeper mid-channel; ripple
	// modulates it so the water isn't a flat wash.
	float bank = smoothstep(0.0, 0.34, uv.y) * smoothstep(1.0, 0.66, uv.y);
	vec3 col = mix(deep_col.rgb, shallow_col.rgb, clamp(ripple * 0.55 + bank * 0.28, 0.0, 1.0));

	// Crest the noise into brighter wave fronts so the surface reads as moving
	// water even in a still frame (units draw strictly on top, so this is free).
	float crest = smoothstep(0.52, 0.78, ripple);
	col += vec3(0.10, 0.17, 0.19) * crest * 1.3;

	// Animated sun-glint: a broad specular band drifting across, broken by ripple.
	float glintband = 0.5 + 0.5 * sin(uv.x * 3.2 + uv.y * 6.0 - TIME * 1.4);
	float glint = smoothstep(0.70, 1.0, glintband * (0.55 + 0.5 * ripple));
	col += vec3(0.58, 0.64, 0.55) * glint * 0.40;

	// Shore foam at the top/bottom edges where the noise peaks.
	float foam = smoothstep(0.90, 1.0, ripple) * (1.0 - bank);
	col += vec3(0.42, 0.46, 0.44) * foam * 0.35;

	// Dry ford: fade the water to transparent across the crossing so the sand
	// strip (drawn over the grass gap in main.gd) reads as a dry path; a soft
	// margin gives a shallow, muddy edge on each side.
	float df = abs(uv.x - ford_center);
	float alpha = smoothstep(ford_halfw, ford_halfw + 0.03, df);   // 0 in ford, 1 outside

	COLOR = vec4(col, alpha);
}
