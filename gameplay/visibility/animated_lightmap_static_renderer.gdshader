shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray direct_layers : filter_linear, repeat_disable;
uniform sampler2D tile_light_lookup : filter_nearest, repeat_disable;
uniform sampler2D light_states : filter_nearest, repeat_disable;
uniform int page_layer_base = 0;
uniform int page_layer_count = 0;

float lookup_slot_state_u(int slot, float tile_lookup_v) {
	vec4 first = texture(tile_light_lookup, vec2(0.25, tile_lookup_v));
	vec4 second = texture(tile_light_lookup, vec2(0.75, tile_lookup_v));
	if (slot == 0) { return first.r; }
	if (slot == 1) { return first.g; }
	if (slot == 2) { return first.b; }
	if (slot == 3) { return first.a; }
	if (slot == 4) { return second.r; }
	if (slot == 5) { return second.g; }
	if (slot == 6) { return second.b; }
	if (slot == 7) { return second.a; }
	return -1.0;
}

vec3 read_local_slot(int slot, vec2 atlas_uv, float tile_lookup_v) {
	if (slot < 0 || slot >= page_layer_count) {
		return vec3(0.0);
	}
	float state_u = lookup_slot_state_u(slot, tile_lookup_v);
	if (state_u < 0.0) {
		return vec3(0.0);
	}
	float irradiance = texture(
		direct_layers,
		vec3(atlas_uv, float(page_layer_base + slot))
	).r;
	vec4 state = texture(light_states, vec2(state_u, 0.5));
	return state.rgb * irradiance * state.a;
}

void fragment() {
	float tile_lookup_v = COLOR.a;
	vec3 direct = vec3(0.0);
	direct += read_local_slot(0, UV, tile_lookup_v);
	direct += read_local_slot(1, UV, tile_lookup_v);
	direct += read_local_slot(2, UV, tile_lookup_v);
	direct += read_local_slot(3, UV, tile_lookup_v);
	direct += read_local_slot(4, UV, tile_lookup_v);
	direct += read_local_slot(5, UV, tile_lookup_v);
	direct += read_local_slot(6, UV, tile_lookup_v);
	direct += read_local_slot(7, UV, tile_lookup_v);

	vec3 authored_albedo = COLOR.rgb;
	ALBEDO = authored_albedo;
	ROUGHNESS = clamp(UV2.x, 0.0, 1.0);
	METALLIC = clamp(UV2.y, 0.0, 1.0);
	EMISSION = authored_albedo * direct;
}
