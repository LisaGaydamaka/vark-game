shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_albedo : source_color = vec4(1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 1.0;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D animated_direct_light : filter_linear, repeat_disable;

void fragment() {
	ALBEDO = base_albedo.rgb;
	ROUGHNESS = base_roughness;
	METALLIC = base_metallic;
	EMISSION = texture(animated_direct_light, UV2).rgb;
}
