shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray direct_layers : filter_linear, repeat_disable;
uniform sampler2D light_states : filter_nearest, repeat_disable;
uniform int light_count = 1;
uniform int page_layer_base = 0;
uniform int page_layer_count = 0;

varying flat vec4 light_ids_0_3;
varying flat vec4 light_ids_4_7;

void vertex() {
	light_ids_0_3 = CUSTOM0;
	light_ids_4_7 = CUSTOM1;
}

vec4 read_light_state(float encoded_index) {
	int index = int(round(encoded_index)) - 1;
	if (index < 0 || index >= light_count) {
		return vec4(0.0);
	}
	float u = (float(index) + 0.5) / float(light_count);
	return texture(light_states, vec2(u, 0.5));
}

vec3 read_local_slot(int slot, float encoded_index, vec2 atlas_uv) {
	if (slot < 0 || slot >= page_layer_count || encoded_index < 0.5) {
		return vec3(0.0);
	}
	float irradiance = texture(
		direct_layers,
		vec3(atlas_uv, float(page_layer_base + slot))
	).r;
	vec4 state = read_light_state(encoded_index);
	return state.rgb * irradiance * state.a;
}

void fragment() {
	vec3 direct = vec3(0.0);
	direct += read_local_slot(0, light_ids_0_3.x, UV);
	direct += read_local_slot(1, light_ids_0_3.y, UV);
	direct += read_local_slot(2, light_ids_0_3.z, UV);
	direct += read_local_slot(3, light_ids_0_3.w, UV);
	direct += read_local_slot(4, light_ids_4_7.x, UV);
	direct += read_local_slot(5, light_ids_4_7.y, UV);
	direct += read_local_slot(6, light_ids_4_7.z, UV);
	direct += read_local_slot(7, light_ids_4_7.w, UV);

	vec3 authored_albedo = COLOR.rgb;
	ALBEDO = authored_albedo;
	ROUGHNESS = clamp(UV2.x, 0.0, 1.0);
	METALLIC = clamp(UV2.y, 0.0, 1.0);
	EMISSION = authored_albedo * direct;
}
