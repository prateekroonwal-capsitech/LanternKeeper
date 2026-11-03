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
| 3 | Cracks (Prompt 4, easy) | Solvable | proof bot PASS — exit in 13 s; dark death; shortcut blocked |
| 4 | The Lid | Solvable | route bot PASS (11.1 s) |
| 5 | Ceiling (rebuilt) | Solvable | proof bot PASS — intended solution + 2 shortcuts blocked |
| 6 | The Lift (remade) | Solvable | proof bot PASS — solution, 2 shortcuts blocked, falling behind kills |
| 7 | Followed (Prompt 4, medium) | Solvable | proof bot PASS — exit in 23 s; 60 % of dark meter used; hesitating kills; shortcut blocked |
| 8 | Lost Light | Solvable | route bot PASS (13.2 s) |
| 9 | Holes (remade) | Solvable | proof bot PASS — solution, carrying the lantern can't grab the rope |
| 10 | The Chase (hard) | Solvable | proof bot PASS — exit in 62.5 s with no attack, swoops miss; standing / going back gets caught; resets at each checkpoint |

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

## 1-3 Cracks — Crawler introduction (EASY) — *Prompt 4 design*
**Idea:** crawlers live in the dark; the lantern keeps you safe.
**Layout:** a shrine right before a gate; a hook beside the gate; one crawler crack at the
foot of the gate wall on each side. The lantern's light is generous here (radius 5.5 m).
**Solution:**
1. Touch the shrine (x 11).
2. Set the lantern down at the hook (x 15) — it hangs, and the gate (x 21) slides open.
3. The crawlers wake (hint: "Stay in the light"). Stay by the hook, inside its light: the near
   crawler freezes at the light's edge and slips back into its crack; the far one stops at the edge.
4. Wait for the gate to finish opening, take the lantern back (step out of reach, walk back in).
5. Walk through the gate carrying it (≈ 1.2 s); the crawlers freeze and retreat. Exit at x 36.
**Difficulty:** easy — no dark walking on the intended path; the shrine is 4 m from the hook;
the gate stays open 3 s after you take the lantern (1.2 s needed).
**Soft-lock checks:** gate shut before you reached it → hang the lantern again; walked through
without the lantern → the crawlers catch you in the dark (respawn at the shrine, lantern in
hand, gate shut, crawlers dormant); no pits; level ends sealed by walls; gate reaches the ceiling.

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

## 1-7 Followed — Stalker introduction (MEDIUM) — *Prompt 4 design*
**Idea:** leave the light behind, with something that punishes you for being away from it.
**Layout:** shrine → switch plate → 22 m of dark floor → door → sanctuary shrine + lever →
the switch's chain carries the lantern through the door to you → two pit jumps → exit.
**Solution:**
1. Touch the first shrine (x −2). Set the lantern on the switch (x 4): the door (x 26) opens,
   and the Stalker wakes behind you (hint: "Something follows. Keep moving").
2. Walk straight to the door (≈ 4.2 s — about 70 % of the 6 s dark meter). The Stalker follows.
3. Through the door is a shrine with a small sanctuary light (radius 2.8 m) the Stalker can't
   enter. Walk into the lever (x 33): the switch rides its chain through the open door and
   delivers the lantern to you (4 s).
4. Take the lantern and carry it over the two pits to the exit (x 76). The Stalker can't come close.
**Difficulty:** medium — a direct walk leaves ≈ 1.8 s of dark meter to spare; hesitating
empties it, the Stalker speeds up and catches you. No route ever leads back past the Stalker.
**Soft-lock checks:** the lever is only reachable through the door, i.e. while the lantern sits
on the switch, so pulling it always delivers the lantern; take the lantern off the switch early
→ the door shuts on your side (place it again); death → respawn at the last shrine with the
switch/chain/lever state of that checkpoint; pits have kill zones; bounds sealed.

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

## 1-10 The Chase — final test of World 1 (HARD but fair) — *Prompt 4 design (updated with The Shade)*
**Idea:** everything learned, under pressure: carry the light, read ghost paths, keep moving.
**Layout:** three ≈ 20 s segments, each ending at a shrine. The Shade (flying shadow chaser) wakes behind you
(hint: "Run") and chases along a 3D flight path at 4.6 m/s with swoops over gaps — slower than the child's 5.2 m/s run, so a clean run
always escapes. Ghost bridges and ghost stepping stones appear in the carried light as you
reach them; cracked plank bridges collapse 0.5 s after you step on them (so you can't stop on
them). At the end, the exit gate opens only while the lantern sits on its plate.
**Solution:**
1. Run right; hop the gaps; cross ghost bridges and stones in your own light.
2. Cross each cracked plank bridge without stopping.
3. Shrines at x 2, 104 and 206 (≈ every 20 s). After a death the Shade restarts at that
   checkpoint's path offset (`checkpoint_offsets`) with every timer cleared, waits 1 s, then
   resumes the chase; collapsed planks and ghost paths reset to the checkpoint.
4. Final segment: set the lantern on the exit plate (x 292) — the gate (x 295) opens — walk
   through to the exit (x 300).
**The Shade's rules:** it flies the `ChasePath` about 6 m behind you and never closes in by
itself, so a child who keeps moving is never attacked. It attacks only when you're stuck:
less than 1 m forward in 3 s (time in the air doesn't count), more than 2 m back, or closer
than 2 m. Then: warning 1.5 s (screech, eyes flare, it closes in a little; moving forward
cancels it) → pull-up 0.5 s → dive at where you are (+ velocity × 0.3) → caught, or it climbs
back and waits 2.5 s. Three scripted swoops dip over the stepping stones (x 60) and the ghost
bridges (x 164, x 248) just after you pass; standing still in a swoop's danger zone
(`SwoopDangerZone1-3`) as it dips gets you caught.
**Difficulty:** hard — no stopping on planks, chained jumps, and the Shade attacks if you
hesitate; every hazard is on screen ≈ 8 m before you reach it; all jumps ≤ 2.4 m (touch-friendly).
**Soft-lock checks:** every pit has a kill zone; the lantern never leaves your hand until the
exit plate (placed there, the gate opens; take it back and it shuts — place it again); planks
reset with checkpoints; bounds sealed by walls.

---

## Tutorial hints (Prompt 4)
One line of light text at the bottom of the screen, once per save; data in
`TutorialManager.HINTS`, text in `strings.csv` (touch gestures / classic touch buttons / PC).

| Level | Trigger | Text (PC · Android gestures · Android buttons) | Placed |
|---|---|---|---|
| 1-1 | level start (`Hint_move`, at spawn) | A/D to move · Space to jump / Drag to move · Tap to jump / Buttons to move and jump | yes |
| 1-1 | before the ghost bridge (`Hint_ghost`, x 12.5) | Light makes paths | yes |
| 1-2 | before the place spot (`Hint_place`, x 9) | E to place lantern / Swipe down to place lantern / Lantern button to place it | yes |
| 1-3 | crawlers wake (`HintStayInLight`, on_wake_group gate_crawlers) | Stay in the light | yes |
| 1-5 | first dropper in view | Danger above | **to place:** TutorialTrigger, hint_id `danger_above`, a few metres before Dropper1 |
| 1-7 | Stalker wakes (`HintSomethingFollows`, on_wake_group stalk7) | Something follows. Keep moving | yes |
| 1-9 | swarm wakes | Light seals the holes | **to place:** TutorialTrigger, hint_id `seal_holes`, on_wake_group `swarm9` (position doesn't matter) |
| 1-10 | chase starts (`HintRun`, on_wake_group chase) | Run | yes |
