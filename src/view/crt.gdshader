shader_type canvas_item;
render_mode blend_mix;

// Subtle arcade scanlines for the 640x360 integer-scaled frame: odd rows darken
// a touch, even rows pass through untouched. No screen reads, fixed math only —
// renders identically on gl_compatibility (screenshot/movie backend) and Forward+.
uniform float strength : hint_range(0.0, 0.3) = 0.08;

void fragment() {
	COLOR = vec4(0.0, 0.0, 0.0, mod(floor(FRAGCOORD.y), 2.0) * strength);
}
