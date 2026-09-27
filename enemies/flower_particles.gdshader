shader_type canvas_item;
render_mode unshaded;

uniform int pattern = 2;
uniform float radius = 80.0;
uniform float inner_radius = 72.0;
uniform float petal_half_width = 36.0;
uniform bool flowing_petals = false;
uniform float warning_seconds = 1.1;
uniform float impact_lifetime = 0.55;
// Updated once per physics tick, using the same clock as damage resolution.
uniform vec3 phase = vec3(0.0); // warning age, impact age, detonated
uniform vec4 main_color : source_color = vec4(1.0, 0.43, 0.08, 1.0);
uniform vec4 orange : source_color = vec4(1.0, 0.43, 0.08, 1.0);
uniform vec4 blue : source_color = vec4(0.12, 0.58, 1.0, 1.0);
uniform vec4 purple : source_color = vec4(0.64, 0.22, 1.0, 1.0);

varying vec2 particle_coord;
varying vec4 particle_color;
varying float spark;
varying float glow;

vec2 rotated(vec2 point, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(c * point.x - s * point.y, s * point.x + c * point.y);
}

void vertex() {
	vec4 seed = INSTANCE_CUSTOM;
	float age = phase.x;
	float impact_age = phase.y;
	bool detonated = phase.z > 0.5;
	float progress = clamp(age / max(warning_seconds, 0.05), 0.0, 1.0);
	float fade = 1.0 - clamp(impact_age / max(impact_lifetime, 0.001), 0.0, 1.0);
	float opacity = detonated ? fade : mix(0.35, 0.95, progress);
	float motion_time = age * 0.3 + age * progress * 0.35 + impact_age;
	float angle = TAU * seed.x;
	vec2 center;
	float orientation;

	if (pattern == 1) {
		float speed = flowing_petals ? 1.25 : 0.4;
		float travel = fract(seed.x + motion_time * speed);
		float sideways = sin(seed.y * TAU + motion_time * 2.0) * 0.94;
		float start = min(18.0, radius * 0.15);
		center = vec2(mix(start, radius, travel), sideways * sin(PI * travel) * petal_half_width);
		if (flowing_petals && !detonated) {
			// The parryable stream gathers beside the boss during its warning.
			// Extend to full reach only on the same physics tick that resolves the hit.
			float bud_start = min(radius * 0.35, 28.0);
			center.x = mix(bud_start, min(radius, bud_start + 22.0), travel);
			center.y *= 0.3;
		}
		orientation = sideways * 0.5;
	} else if (pattern == 0) {
		angle += motion_time * (0.7 + seed.z * 0.7);
		float distance = sqrt(mix(inner_radius * inner_radius, radius * radius, seed.y));
		center = vec2(cos(angle), sin(angle)) * distance;
		orientation = angle + PI * 0.5;
	} else {
		angle += motion_time * 0.8;
		float lobe = 0.78 + 0.22 * cos(angle * 5.0);
		center = vec2(cos(angle), sin(angle)) * radius * lobe * sqrt(seed.y) * 0.98;
		orientation = angle + PI * 0.5;
	}
	if (detonated) {
		vec2 direction = pattern == 1 ? vec2(1.0, 0.0) : center / max(length(center), 0.001);
		center += direction * impact_age * (24.0 + seed.z * 48.0);
	}

	int color_index = INSTANCE_ID % 3;
	vec3 color = color_index == 0 ? orange.rgb : (color_index == 1 ? blue.rgb : purple.rgb);
	color = mix(color, main_color.rgb, 0.2);
	float twinkle = 0.8 + 0.2 * sin((age + impact_age) * 18.0 + seed.w * TAU);
	float size = mix(1.6, 4.2, seed.z) * (detonated ? 1.25 : 0.8 + progress * 0.2);
	float alpha = opacity * twinkle * (0.6 + seed.w * 0.4);
	particle_color = vec4(color, alpha) * COLOR;
	spark = INSTANCE_ID % 3 == 0 ? 1.0 : 0.0;
	glow = INSTANCE_ID % 8 == 0 ? 1.0 : 0.0;
	float extent = glow > 0.5 ? 2.6 : 1.1;
	particle_coord = (UV * 2.0 - 1.0) * extent;
	orientation += sin(motion_time * 4.0 + seed.w * TAU);
	VERTEX = center + rotated(particle_coord * size, orientation);
}

void fragment() {
	// One shared quad becomes a petal, spark, and optional faint halo in one pass.
	float distance = length(particle_coord);
	float aa = max(length(fwidth(particle_coord)) * 0.5, 0.01);
	float core;
	if (spark > 0.5) {
		core = 1.0 - smoothstep(0.55 - aa, 0.55 + aa, distance);
	} else {
		// Match the original eight-vertex petal silhouette without rebuilding it.
		float x = abs(particle_coord.x);
		float half_width = x < 0.5 ? mix(0.48, 0.339411, x * 2.0)
			: mix(0.339411, 0.0, (x - 0.5) * 2.0);
		float edge = max(x - 1.0, abs(particle_coord.y) - half_width);
		core = 1.0 - smoothstep(-aa, aa, edge);
	}
	float core_alpha = core * particle_color.a;
	float halo_alpha = (1.0 - smoothstep(2.5 - aa, 2.5 + aa, distance)) * glow * particle_color.a * 0.09;
	float alpha = core_alpha + halo_alpha * (1.0 - core_alpha);
	vec3 core_color = mix(particle_color.rgb, vec3(1.0), spark * 0.25);
	vec3 color = (core_color * core_alpha + particle_color.rgb * halo_alpha * (1.0 - core_alpha))
		/ max(alpha, 0.0001);
	COLOR = vec4(color, alpha);
}
