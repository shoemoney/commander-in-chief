shader_type canvas_item;
render_mode blend_mix;

// Subtle arcade scanlines for the 640x360 integer-scaled frame: odd rows darken
// a touch, even rows pass through untouched. No screen reads, fixed math only —
// renders identically on gl_compatibility (screenshot/movie backend) and Forward+.
uniform float strength : hint_range(0.0, 0.3) = 0.08;
// Radial vignette folded into the same pass: darkens corners past ~55% of the
// half-diagonal. max() with the scanline alpha so neither effect stacks double.
uniform float vignette_strength : hint_range(0.0, 0.5) = 0.18;
// The logical canvas. The scanline row comes from UV x this, so a canvas pixel gets a
// consistent line at any integer scale (window-pixel coordinates are wrong when the
// stretch mode is not "viewport").
uniform vec2 canvas_size = vec2(640.0, 360.0);

void fragment() {
	float scan = mod(floor(UV.y * canvas_size.y), 2.0) * strength;
	float vig = smoothstep(0.55, 0.95, distance(UV, vec2(0.5))) * vignette_strength;
	COLOR = vec4(0.0, 0.0, 0.0, max(scan, vig));
}
