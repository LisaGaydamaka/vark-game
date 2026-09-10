# Player Movement Regression Checklist

Use this checklist before and after player-controller refactors. The current `test` branch behavior is the baseline.

## Ground and support

- [ ] Walk and sprint on flat ground.
- [ ] Walk up, down, and across walkable slopes.
- [ ] Land normally from a jump and from a longer fall.
- [ ] Fall while rubbing against a wall without the fall being cancelled.
- [ ] Fall past modular wall seams and convex edges without becoming stuck or gaining fake support.

## Steps

- [ ] Walk straight into valid steps and climb them smoothly.
- [ ] Approach valid steps diagonally and sideways where expected.
- [ ] Walk into wall seams near foot height without them being treated as steps.
- [ ] Jump or fall into stair/step geometry without an airborne step starting.
- [ ] Step from slopes and other valid support surfaces without an unexpected height change.

## Crouch and jump

- [ ] Crouch and stand repeatedly on flat ground.
- [ ] Move while crouched and verify crouch speed.
- [ ] Jump while walking and sprinting.
- [ ] Verify air steering and landing behavior.

## Ledge traversal

- [ ] Grab a ledge from a normal jump.
- [ ] Grab a ledge while falling alongside nearby wall geometry.
- [ ] Shimmy/hang without unexpected support or step transitions.
- [ ] Move around a ledge corner.
- [ ] Mantle successfully from valid ledges.
- [ ] Drop or jump away from a ledge without immediately re-entering an invalid traversal state.

## Baseline rule

If a refactor changes any item above, treat it as a regression unless the behavior change is intentional and documented.
