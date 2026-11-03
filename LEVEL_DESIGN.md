# Lantern Keeper — World 1 level design & solvability

Rules used for every level: the level can't be finished without its mechanic; every pit has
a kill zone; level ends are sealed by walls; a shrine sits before each hard section; no
trap is escapable only by dying (a lantern that falls into a pit reappears beside the child).

Status legend — **Solvable**: completed end-to-end by the route bot in the running game.
**Not solvable**: verified by analysis against the current rules (explained).

| # | Level | Status | Proof |
|---|---|---|---|
| 1 | First Light | Solvable | route bot PASS (12.4 s) |
| 2 | Leave It Behind | Solvable | route bot PASS (7.5 s) |
| 3 | Cracks (rebuilt) | Solvable | proof bot PASS — intended solution + death path |
| 4 | The Lid | Solvable | route bot PASS (11.1 s) |
| 5 | Ceiling (rebuilt) | Solvable | proof bot PASS — intended solution + 2 shortcuts blocked |
| 6 | The Lift (remade) | Solvable | proof bot PASS — solution, 2 shortcuts blocked, falling behind kills |
| 7 | Followed (remade) | Solvable | proof bot PASS — solution, shortcut blocked, dawdling kills |
| 8 | Lost Light | Solvable | route bot PASS (13.2 s) |
| 9 | Holes (remade) | Solvable | proof bot PASS — solution, carrying the lantern can't grab the rope |
| 10 | The Dark Tide (Big Shadow chase) | Solvable | route bot PASS (18.4 s) |

All 10 levels are solvable. Levels 3, 5, 6, 7 and 9 follow the remake brief; levels 1, 2,
4, 8 and 10 are still the original Phase 5 layouts (solvable, not yet reworked to the brief).

---

## 1-1 First Light — carry the light; ghost floors appear around you
1. Walk right; jump the first small gap.
2. The ghost bridge over the pit turns solid as the carried light reaches it — walk across.
3. Climb the two ghost steps to the high ledge; jump the ghost gap; reach the exit.
- Shortcut check: every gap is a pit with a kill zone; no real floor bypasses a ghost.
- Soft-lock check: none — the lantern never leaves the child.

## 1-2 Leave It Behind — light makes ghost walls solid
1. Cross the ghost bridge carrying the light.
2. The ghost wall under the ceiling is solid while lit — set the lantern down ≥ 4.5 m before it.
3. Walk through the wall in darkness to the exit.
- Shortcut check: the wall reaches the ceiling (no jump over it).
- Soft-lock check: placing the lantern too close keeps the wall solid — walk back, pick it up, retry.

## 1-3 Cracks (rebuilt) — crawlers; hang the lantern to open the gate
1. A crawler bursts from a floor crack at x 9 — it meets the carried light, freezes, hisses
   and slips back into its crack (lesson: light protects you).
2. At the hook (x 15) set the lantern down: it **hangs on the hook** and the gate (x 24)
   slides open. Hanging it also wakes two crawlers in the cracks before the gate.
3. Take the lantern back off the hook (step out of reach, walk back in). The gate stays open
   for 3 s, then shuts.
4. Walk through the gate carrying the light — the crawlers can't come near.
5. Cross the ghost bridge (needs the light), carry the light past two more crawlers, exit.
- Shortcut checks: the gate reaches the ceiling (no jump over); the gate only opens while the
  lantern hangs; going through without the lantern → crawlers catch you in the dark
  (proof log: woke → emerged → hunt → telegraph → caught), and the bridge beyond needs light.
- Soft-lock checks: gate shut before you reached it → hang the lantern again; went through
  without the lantern → the gate stays open while it hangs, walk back for it; death → respawn
  at the shrine with the lantern state from that checkpoint, gate closed, crawlers dormant.

## 1-4 The Lid — light the climb, not the lid
1. Enter the shaft, climb the first ghost step to the solid shelf, set the lantern on the shelf.
2. The shelf lantern lights the upper ghost steps but not the lid above (4.65 m away).
3. Climb the steps and jump up through the dark lid to the exit plateau.
- Shortcut check: carrying the lantern up lights the lid — it blocks the jump.
- Soft-lock check: lantern placed elsewhere → steps stay dark; walk back and pick it up.

## 1-5 Ceiling (rebuilt) — droppers; dash through a gated tunnel in the dark
1. Two droppers hang from the cave ceiling — carry the light under them; they pull up and hiss.
2. Hang the lantern on the **rail hook** (x 20.5): the tunnel gate (x 25) opens only while it hangs.
3. Dash through the dark tunnel. The tunnel droppers let go 0.3 s after you pass under —
   keep running and they land behind you.
4. At the far end, walk into the **lever** (x 46): the rail carries the hanging lantern
   through the tunnel to you (4 s). Take it.
5. Touch the shrine, cross the ghost bridge (needs light), carry the light under two more
   droppers, exit.
- Shortcut checks (proof bot): carrying the light into the tunnel → the gate is shut (blocked);
  hanging the lantern then grabbing it and running → the gate shuts in 0.3 s before you reach it
  (blocked); skipping the lantern after the tunnel → the ghost bridge needs light.
- Soft-lock checks: the lever is only reachable through the open gate, i.e. while the lantern
  hangs on the hook, so pulling it always brings the lantern; death → checkpoint snapshot
  restores hook, gate, lever and lantern; no ghost walls in this level.
- Deviation from the brief: the brief's reason for leaving the light ("too low to walk through
  holding the light up") is replaced by the hook-gate, which forces the dark dash without a
  ghost wall on the main path.

## 1-6 The Lift (remade) — keep pace with a moving light
1. Hang the lantern on the **cradle** (x 6.5). The gate (x 11.2) opens while it hangs, and the
   cradle starts riding its rail across the chasm (34 m in 11 s).
2. Drop onto the ghost stones and follow beneath it — each stone is solid only while the
   cradle's light is over it. Run ahead and you jump onto a dark stone; fall behind and the
   stone under you fades.
3. At the far ledge the cradle stops; walk into the lantern to take it. Shrine, exit.
- Shortcut checks (proof bot): carrying the light through the gate → shut; snatching the
  lantern back off the moving cradle → not allowed (a lantern can only be taken from a hook
  that has stopped).
- Soft-lock checks: falling behind → death → respawn at the shrine with the lantern in hand
  and the cradle back at its start. Stones are 2.5 m wide with 2 m gaps (touch-friendly).

## 1-7 Followed (remade) — the light stays on a switch; the Stalker follows
1. Set the lantern on the **switch** (x 8): it holds the gate (x 16) open — and wakes the
   Stalker behind you.
2. Run the long dark stretch to the shrine (x 30). This shrine is a **sanctuary**: a small
   light the Stalker can't enter, where the dark meter refills.
3. Leave and keep running — two pit jumps — to the exit. Linger in the dark and the vignette
   closes in and the Stalker catches you.
- Shortcut checks: carrying the light through the gate → shut (the gate only opens while the
  lantern sits on the switch; taking it off shuts the gate long before you reach it).
- Soft-lock checks: the lantern stays behind by design (the level ends in the dark); death →
  respawn at the sanctuary with the lantern still on its switch and the gate open.

## 1-9 Holes (remade) — seal two holes, swing past the third
1. A **rope** hangs over a wide pit. It takes both hands — you can't grab it while carrying
   the lantern.
2. Set the lantern down between the two floor holes (x 8 and 12): their light seals them.
3. Run and jump onto the rope — grabbing it wakes the swarm. The third hole, in the pit wall
   behind the rope, pours out mites behind you. Let go on the upswing, land on the far side,
   outrun the mites to the exit.
- Shortcut checks: jumping at the rope while carrying the light → no grab → fall (proof bot).
- Soft-lock checks: the lantern stays behind by design (short final run); lantern placed so
  it doesn't cover both holes → those mites chase you too (harder, not stuck); death → respawn
  with the lantern in hand and every hole sealed again.

## 1-8 Lost Light — start without the lantern
1. In darkness, cross the solid blocks to the perch where the lantern sits.
2. Pick it up; cross the ghost bridges it lights.
3. Drop to the floor; set the lantern down ≥ 4.5 m before the ghost wall; walk through.

## 1-10 The Dark Tide — Big Shadow chase
1. The Big Shadow wakes behind you — keep moving; carry the light over the ghost floors.
2. Shrine mid-way (the Big Shadow restarts behind it after a death).
3. Final ghost wall: set the lantern down and run through to the exit.
- Note: the Big Shadow ignores light; it can only be outrun.
