# Player Controller Regression Checklist

Use this checklist after player-controller refactors. The current `test` branch behavior is the baseline unless a behavior change is explicitly intentional and documented.

## Project load and structure

- [ ] Close and reopen the Godot project with no missing-script, global-class, UID, parser, or GDScript warning errors from player code.
- [ ] `Player.tscn` loads and the player spawns normally.
- [ ] No unexpected `.gd.uid` files are generated after the project rescan.

## Input and look

- [ ] Walk in all four directions and diagonally.
- [ ] Mouse look works normally through the full allowed pitch range.
- [ ] Mouse capture/release behavior still works as expected.
- [ ] Simultaneous movement inputs, jump, crouch, and sprint do not produce stale one-frame input states.

## Ground, support, and slopes

- [ ] Walk and sprint on flat ground.
- [ ] Start and stop cleanly with expected acceleration/deceleration.
- [ ] Walk up, down, and across walkable slopes.
- [ ] Stand still on walkable slopes without unexpected sliding when static friction should hold.
- [ ] Land normally from a jump and from a longer fall.
- [ ] Walk off platform edges and begin falling immediately.
- [ ] Stand on narrow beams/edges that physically support the capsule.
- [ ] Fall while rubbing against a wall without the fall being cancelled.
- [ ] Fall past modular wall seams and convex edges without becoming stuck or gaining fake support.
- [ ] With no horizontal input, falling contact must never manufacture a large sideways displacement or launch.

## Steps

- [ ] Walk straight into valid steps and climb them smoothly.
- [ ] Approach valid steps diagonally and climb them smoothly.
- [ ] Face along a step and strafe sideways onto it successfully.
- [ ] Strafe along a riser without inward movement and verify a step does not start.
- [ ] Walk into wall seams near foot height without them being treated as steps.
- [ ] Jump or fall into stair/step geometry without an airborne step starting.
- [ ] Step from slopes and other valid source-support surfaces without an unexpected height change.
- [ ] Test multiple valid step heights up to the configured maximum.
- [ ] A blocked overhead/crossing route does not force the capsule through geometry.

## Crouch, sprint, jump, and air control

- [ ] Crouch and stand repeatedly on flat ground.
- [ ] Crouch under low clearance and verify standing is blocked until clearance exists.
- [ ] Move while crouched and verify crouch speed.
- [ ] Sprint while fully standing and verify sprint speed.
- [ ] Jump from standstill, walking, and sprinting.
- [ ] Jump releases walkable support immediately and does not get re-grounded during ascent.
- [ ] Verify air steering, reversal, and landing behavior.
- [ ] Hold jump through an airborne attempt and verify mantle intent remains armed only for that attempt.
- [ ] Release jump and verify mantle intent/rearm behavior resets correctly.

## Ledge detection and hanging

- [ ] Grab a ledge from a normal jump.
- [ ] Grab a ledge while falling alongside nearby wall geometry.
- [ ] Hang without unexpected support or step transitions.
- [ ] Shimmy left and right across valid ledges.
- [ ] Traverse inside/outside ledge corners where supported.
- [ ] Directional jump from a hang works at normal speed.
- [ ] Sprint directional ledge jump uses the expected launch speed.
- [ ] No-input hang jump works and releases the ledge cleanly.

## Traversal guards

- [ ] Jump away from a ledge and verify the same ledge cannot be immediately regrabbed during the suppressed region.
- [ ] After moving/reaching the allowed region again, verify that ledge can be grabbed normally.
- [ ] Drop from a ledge and verify no immediate same-ledge regrab.
- [ ] A failed catch does not immediately loop into the same catch.
- [ ] A failed mantle while jump remains held does not repeatedly retry the same mantle.
- [ ] Releasing/re-pressing jump allows a legitimate later mantle attempt.
- [ ] Releasing from a corner does not immediately reacquire the released corner.

## Mantle

- [ ] Ground-requested mantle starts only from a valid contacted ledge.
- [ ] Airborne jump-hold mantle buffering works.
- [ ] Mantle a normal wide platform successfully.
- [ ] Mantle the 0.125-thick fence successfully.
- [ ] Successful mantle completes when the body center reaches the ledge plane.
- [ ] Successful mantle ends with exactly zero intended player velocity rather than carrying forward motion.
- [ ] After the thin-fence mantle, remain supported instead of sinking, sticking, or falling through the top edge.
- [ ] The thin-fence mantle produces no backward snap after completion.
- [ ] Walk off both sides of the thin fence normally after mantling.
- [ ] Jump from the thin fence normally after mantling.

## Velocity and collision ownership

- [ ] Ordinary locomotion behaves identically with controlled velocity routed through `PlayerVelocityState`.
- [ ] Traversal entry/release does not leave stale locomotion velocity in the next normal-movement frame.
- [ ] A walkable landing may terminate downward controlled velocity only after `PlayerSupport` validates the contact.
- [ ] Unsupported collision response may constrain or redirect requested motion, but must not create a displacement longer than the requested motion.
- [ ] Collision response does not convert a few millimeters of gravity into a large horizontal movement at floor-like edge normals.

## Baseline rule

If a refactor changes any item above, treat it as a regression unless the behavior change is intentional and documented.
