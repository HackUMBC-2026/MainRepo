shader_type canvas_item;
render_mode unshaded, skip_vertex_transform;
uniform int kind = 0; // 0: expanding ring, 1: blade, 2: wake
uniform float age = 0.0;
uniform float radius = 150.0;
uniform float span = 20.0;
varying vec4 tint;
void vertex() {
	vec4 seed = INSTANCE_CUSTOM;
	float phase = fract(seed.y + age * 2.0);
	float fade = max(0.0, 1.0 - age / 0.7);
	vec2 center;
	if (kind == 0) {
		float angle = seed.x * TAU;
		float reach = min(age / 0.22, 1.0) * radius;
		float distance = max(0.0, reach - seed.y * 6.0);
		if (seed.w < 0.5) {
			// Travel with the wave, then remain scattered across the ground.
			float deposit_radius = sqrt(seed.z) * radius;
			float deposit_time = 0.22 * sqrt(seed.z);
			distance = min(reach, deposit_radius);
			fade = 1.0 - clamp((age - deposit_time) / (0.55 + seed.y * 0.3), 0.0, 1.0);
		} else {
			fade = 1.0 - clamp((age - 0.22) / 0.35, 0.0, 1.0);
		}
		center = vec2(cos(angle), sin(angle)) * distance;
	} else if (kind == 1) {
		center = vec2((seed.x - 0.5) * 8.0 + sin(age * 9.0 + seed.z * TAU) * phase * 3.0, seed.z * span - phase * 12.0);
		fade = 1.0 - phase;
	} else {
		center = vec2(seed.x * span, (seed.y - 0.5) * 24.0);
		center.y -= age * (10.0 + seed.z * 28.0);
	}
	// Keep each quad one game pixel and axis-aligned even as the sword rotates.
	vec2 world_center = (MODEL_MATRIX * vec4(center, 0.0, 1.0)).xy;
	VERTEX = floor(world_center) + vec2(0.5) + VERTEX * 0.5;
	tint = vec4(mix(vec3(1.0, 0.22, 0.015), vec3(1.0, 0.9, 0.35), seed.w), fade);
}
void fragment() {
	COLOR = tint;
}
