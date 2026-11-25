shader_type canvas_item;
render_mode unshaded;

// Procedural ocean: ONE full-screen quad, no textures, no loops.
// quality 0 = flat tint, 1 = animated swell + sun glint, 2 = adds whitecaps and fine ripples.
uniform vec2 cam_pos = vec2(0.0);
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform float zoom = 1.0;
uniform float t = 0.0;
uniform float world_size = 3000.0;
uniform int quality = 1;
uniform vec3 deep_col : source_color = vec3(0.008, 0.085, 0.165);
uniform vec3 shallow_col : source_color = vec3(0.035, 0.26, 0.38);

void fragment() {
	vec2 w = cam_pos + (UV - 0.5) * view_size / zoom;
	vec3 col;
	if (quality <= 0) {
		col = mix(deep_col, shallow_col, 0.35);
	} else {
		// sum of travelling sine waves with an analytic gradient (cheap fake normals)
		float p1 = w.x * 0.0075 + w.y * 0.0031 + t * 0.35;
		float p2 = -w.x * 0.0042 + w.y * 0.0091 - t * 0.28;
		float p3 = (w.x + w.y) * 0.0143 + t * 0.55;
		float p4 = (w.x - w.y) * 0.0117 - t * 0.40;
		float h = sin(p1) + sin(p2) + sin(p3) + sin(p4);
		vec2 g = vec2(0.0075, 0.0031) * cos(p1) + vec2(-0.0042, 0.0091) * cos(p2)
			+ vec2(0.0143, 0.0143) * cos(p3) + vec2(0.0117, -0.0117) * cos(p4);
		float ripple = 0.0;
		if (quality >= 2) {
			float p5 = w.x * 0.045 + sin(w.y * 0.03 + t * 0.7) * 2.0 + t * 0.9;
			float p6 = w.y * 0.052 - w.x * 0.021 - t * 1.1;
			ripple = sin(p5) * sin(p6);
			g += vec2(0.045, 0.0) * cos(p5) * 0.4 + vec2(-0.021, 0.052) * cos(p6) * 0.4;
		}
		float n = h * 0.25;
		col = mix(deep_col, shallow_col, 0.5 + n * 0.5);
		// large soft colour variation so the sea never looks tiled
		col *= 0.92 + 0.08 * sin(w.x * 0.0021 + 1.3) * sin(w.y * 0.0017 - 0.7);
		// sun glint: half-vector against a fake normal
		vec3 nrm = normalize(vec3(-g.x * 9.0, -g.y * 9.0, 1.0));
		vec3 hv = normalize(vec3(-0.45, -0.55, 0.70) + vec3(0.0, 0.0, 1.0));
		float spec = pow(max(dot(nrm, hv), 0.0), 80.0);
		col += vec3(0.55, 0.65, 0.70) * spec * 0.55;
		// sparkling sun glitter: tiny flickering facets that only light up near the sun direction
		vec2 cell = floor(w * 0.45 + vec2(t * 0.6, -t * 0.4));
		float hsh = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		float tw = step(0.975, hsh) * pow(max(dot(nrm, hv), 0.0), 6.0);
		col += vec3(0.9, 0.95, 1.0) * tw * 0.7;
		if (quality >= 2) {
			float crest = smoothstep(0.55, 0.95, n + ripple * 0.18);
			col += vec3(0.20, 0.26, 0.28) * crest * 0.5;
		} else {
			float s = sin(w.x * 0.045 + sin(w.y * 0.03 + t * 0.7) * 2.0 + t * 0.8);
			col += vec3(0.04, 0.07, 0.08) * smoothstep(0.92, 1.0, s);
		}
	}
	// world border (outside = darker + red tint)
	float d = max(abs(w.x), abs(w.y)) - world_size;
	if (d > 0.0) {
		col = mix(col * 0.35, vec3(0.35, 0.05, 0.07), 0.25);
	}
	float edge = 1.0 - smoothstep(0.0, 5.0 / zoom, abs(d));
	col = mix(col, vec3(1.0, 0.25, 0.25), edge * 0.9);
	// vignette
	vec2 q = UV - 0.5;
	col *= 1.0 - dot(q, q) * 0.6;
	COLOR = vec4(col, 1.0);
}
