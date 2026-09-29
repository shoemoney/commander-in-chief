shader_type canvas_item;
render_mode unshaded;

// Coordinates are in the game's logical viewport, not window pixels.
uniform vec2 view_size = vec2(640.0, 360.0);
uniform vec2 player_one = vec2(-1000.0);
uniform vec2 player_two = vec2(-1000.0);
uniform float panel_bottom = 0.0;

void fragment() {
	vec2 at = SCREEN_UV * view_size;
	float nearest = min(distance(at, player_one), distance(at, player_two));
	// No time-based flicker or motion: the aperture follows the world position.
	float visibility = mix(0.08, 1.0, smoothstep(19.0, 35.0, nearest));
	COLOR.a *= mix(visibility, 1.0, step(panel_bottom, at.y));
}
