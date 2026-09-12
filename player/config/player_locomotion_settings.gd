class_name PlayerLocomotionSettings
extends Resource


@export_category("Movement")
@export var max_speed: float = 3.0
@export var sprint_speed: float = 4.5
@export var acceleration: float = 28.0
@export var ground_deceleration: float = 15.0


@export_category("Jump")
@export var jump_height: float = 0.75


@export_category("Air")
@export var air_max_speed: float = 2.5
@export var air_acceleration: float = 20.0
@export var air_deceleration: float = 15.0


@export_category("Surface")
@export var max_walkable_slope: float = 45.0
@export var support_check_distance: float = 0.05
@export var static_friction_coefficient: float = 1.0
@export var kinetic_friction_coefficient: float = 0.1


@export_category("Gravity")
@export var gravity: float = 12.0


@export_category("Collision")
@export var max_collision_iterations: int = 8


@export_category("Step Up")
@export var step_max_height: float = 0.5
@export var step_up_acceleration: float = 100.0
@export var step_up_max_speed: float = 30.0
