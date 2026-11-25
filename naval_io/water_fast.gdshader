shader_type canvas_item;
render_mode unshaded;

// Procedural ocean: ONE full-screen quad. All the heavy maths (the sum of travelling waves and their
// slopes) is pre-computed once into a small tileable texture, so each pixel only needs 2-3 texture
// reads and a little lighting - roughly 10x cheaper than evaluating the waves per pixel.
// quality 0 = flat tint, 1 = animated swell + sun glint, 2 = adds fine ripples, whitecaps, sparkle.
uniform vec2 cam_pos = vec2(0.0);
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform float zoom = 1.0;
uniform float t = 0.0;
uniform float world_size = 3000.0;
uniform int quality = 1;
uniform sampler2D wave_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_nearest, repeat_enable;
uniform vec3 deep_col : source_color = vec3(0.008, 0.085, 0.165);
uniform vec3 shallow_col : source_color = vec3(0.035, 0.26, 0.38);

vec3 decode(vec4 s) {
	return vec3(s.r * 2.0 - 1.0, s.g * 2.0 - 1.0, s.b * 2.0 - 1.0);
}

void fragment() {
	vec2 w = cam_pos + (UV - 0.5) * view_size / zoom;
	vec3 col;
	if (quality <= 0) {
		col = mix(deep_col, shallow_col, 0.35);
	} else {
		vec3 a = decode(texture(wave_tex, w * 0.0011 + vec2(t * 0.010, t * 0.006)));
		vec3 b = decode(texture(wave_tex, w * 0.0031 + vec2(-t * 0.013, t * 0.009)));
		float h = a.x * 0.5 + b.x * 0.35;
		vec2 g = a.yz * 0.9 + b.yz * 1.4;
		float ripple = 0.0;
		if (quality >= 2) {
			vec3 c = decode(texture(wave_tex, w * 0.0089 + vec2(t * 0.02, -t * 0.015)));
			h += c.x * 0.2;
			g += c.yz * 2.0;
			ripple = c.x;
		}
		col = mix(deep_col, shallow_col, 0.5 + h * 0.55);
		// soft large-scale colour variation so the sea never looks tiled
		col *= 0.93 + 0.07 * a.x * b.x;
		// sun glint: half-vector against the wave normal
		vec3 nrm = normalize(vec3(-g.x * 0.10, -g.y * 0.10, 1.0));
		vec3 hv = normalize(vec3(-0.45, -0.55, 0.70) + vec3(0.0, 0.0, 1.0));
		float nd = max(dot(nrm, hv), 0.0);
		float spec = pow(nd, 80.0);
		col += vec3(0.55, 0.65, 0.70) * spec * 0.55;
		if (quality >= 2) {
			float crest = smoothstep(0.45, 0.95, h + ripple * 0.25);
			col += vec3(0.20, 0.26, 0.28) * crest * 0.5;
			// sparkling glitter: random facets that only light up near the sun direction
			vec2 cell = floor(w * 0.45 + vec2(t * 0.6, -t * 0.4));
			float rnd = texture(noise_tex, (cell + 0.5) / 64.0).r;
			float n2 = nd * nd;
			float n4 = n2 * n2;
			col += vec3(0.9, 0.95, 1.0) * step(0.975, rnd) * n4 * n2 * 0.7;
		} else {
			col += vec3(0.04, 0.07, 0.08) * smoothstep(0.55, 0.9, h);
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
