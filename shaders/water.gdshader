shader_type canvas_item;

uniform vec4 deep_color : source_color = vec4(0.04, 0.15, 0.27, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.08, 0.3, 0.42, 1.0);
uniform vec2 cam_pos = vec2(0.0, 0.0);

float wave_height(vec2 p, float t) {
	float w = sin(p.x * 0.9 + t * 0.8) * sin(p.y * 1.1 - t * 0.6);
	float w2 = sin((p.x + p.y) * 0.6 + t * 1.3);
	float w3 = sin((p.x - p.y * 0.6) * 1.7 - t * 0.9);
	return 0.5 + 0.22 * w + 0.22 * w2 + 0.16 * w3;
}

void fragment() {
	vec2 p = UV * vec2(1280.0, 720.0) / 48.0 + cam_pos / 48.0;
	float t = TIME;
	float h = wave_height(p, t);
	h = h * 0.7 + wave_height(p * 2.7 + vec2(3.0, -2.0), t * 1.4) * 0.3;
	vec4 col = mix(deep_color, shallow_color, clamp(h, 0.0, 1.0));
	float foam = smoothstep(0.78, 0.82, h);
	col = mix(col, vec4(0.85, 0.95, 1.0, 1.0), foam * 0.22);
	COLOR = col;
}
