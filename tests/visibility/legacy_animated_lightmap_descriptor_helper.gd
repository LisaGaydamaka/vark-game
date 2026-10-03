class_name VarkAnimatedLightmapBaker
extends RefCounted

# Test-only compatibility helper for the 8.4.1A regression. The rejected
# whole-mesh baker was removed in 8.4.1C; only descriptor extraction remains
# here until the A fixture is fully decoupled from the retired class name.
static func descriptor_from_gameplay_light(
	light: VarkGameplayLight
) -> Dictionary:
	if light == null:
		return {}
	return {
		"position": light.get_emitter_global_position(),
		"color": light.light_color,
		"energy": maxf(light.light_energy, 0.0),
		"range": maxf(light.omni_range, 0.001),
	}
