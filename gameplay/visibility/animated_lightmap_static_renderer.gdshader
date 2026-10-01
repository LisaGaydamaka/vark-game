shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray direct_layers : filter_linear, repeat_disable;
uniform sampler2D light_weights : filter_nearest, repeat_disable;
uniform int weight_count = 1;

uniform int layer_0 = -1;
uniform int weight_0 = -1;
uniform vec4 color_0 : source_color = vec4(0.0);
uniform int layer_1 = -1;
uniform int weight_1 = -1;
uniform vec4 color_1 : source_color = vec4(0.0);
uniform int layer_2 = -1;
uniform int weight_2 = -1;
uniform vec4 color_2 : source_color = vec4(0.0);
uniform int layer_3 = -1;
uniform int weight_3 = -1;
uniform vec4 color_3 : source_color = vec4(0.0);
uniform int layer_4 = -1;
uniform int weight_4 = -1;
uniform vec4 color_4 : source_color = vec4(0.0);
uniform int layer_5 = -1;
uniform int weight_5 = -1;
uniform vec4 color_5 : source_color = vec4(0.0);
uniform int layer_6 = -1;
uniform int weight_6 = -1;
uniform vec4 color_6 : source_color = vec4(0.0);
uniform int layer_7 = -1;
uniform int weight_7 = -1;
uniform vec4 color_7 : source_color = vec4(0.0);

float read_weight(int index) {
	if (index < 0 || weight_count <= 0) {
		return 0.0;
	}
	float u = (float(index) + 0.5) / float(weight_count);
	return texture(light_weights, vec2(u, 0.5)).r;
}

vec3 read_contribution(int layer_index, int weight_index, vec3 light_color) {
	if (layer_index < 0 || weight_index < 0) {
		return vec3(0.0);
	}
	float irradiance = texture(
		direct_layers,
		vec3(UV, float(layer_index))
	).r;
	return light_color * irradiance * read_weight(weight_index);
}

void fragment() {
	vec3 direct = vec3(0.0);
	direct += read_contribution(layer_0, weight_0, color_0.rgb);
	direct += read_contribution(layer_1, weight_1, color_1.rgb);
	direct += read_contribution(layer_2, weight_2, color_2.rgb);
	direct += read_contribution(layer_3, weight_3, color_3.rgb);
	direct += read_contribution(layer_4, weight_4, color_4.rgb);
	direct += read_contribution(layer_5, weight_5, color_5.rgb);
	direct += read_contribution(layer_6, weight_6, color_6.rgb);
	direct += read_contribution(layer_7, weight_7, color_7.rgb);

	vec3 authored_albedo = COLOR.rgb;
	ALBEDO = authored_albedo;
	ROUGHNESS = clamp(UV2.x, 0.0, 1.0);
	METALLIC = clamp(UV2.y, 0.0, 1.0);
	EMISSION = authored_albedo * direct;
}
