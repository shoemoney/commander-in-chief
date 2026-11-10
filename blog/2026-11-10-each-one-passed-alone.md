# Each one passed alone

*2026-11-10*

1.5.0 was built as 26 work packages in separate worktrees, each with its own
tests, each green before it was picked onto the branch. The suite went from
1,418 test methods and 48,528 assertions to 1,729 and 96,997.

None of the day's real defects were inside a package. Every one of them was in
the space between two packages, where neither package's tests could look. This
is the record of those, including the three times the first diagnosis was wrong.

## The gun that stopped firing

One package added the flamethrower and the rocket launcher. Another gave the
Bridge Gunship three acts. Both were green.

An independent read of the merged tree asked what happens when a player holding
a flamethrower stands under the gunship. The answer, measured with fire held for
600 ticks: hull 40, then hull 40. The special owned the trigger, the flame cone
could not reach the hull, and the machine gun never got a turn. Time to kill an
MG nest from 100 px with a flamethrower in hand came back as -1, meaning never.

The fix lets a held special own the trigger only while it has something to hit.
The same measurement afterwards: 30 ticks, the machine gun's own number, and no
fuel burned. Rockets had a quieter version of the same problem against a hull
that drifts: 4 of 4, 3 or more of 4, and 0 of 4 hits at 60, 120 and 200 px
before a lead was added, 4 of 4 at all three after.

The weapon tests had targets a weapon can hit. The boss tests had a player with
a machine gun. Nothing was wrong with either.

## The score and the thing that plays it

The soundtrack and the music director were built at the same time against a
written contract. Merged, three director assertions went red.

The director's tests injected their own short fixture streams, but the director
itself read the shipped manifest when it started. On the director's own branch
there was no shipped manifest, so its built-in defaults applied and everything
agreed. After the merge the tests were timing a 0.5 second fixture sting
against the real stinger's 3 to 5 seconds, and a 110 BPM bar against each
track's own tempo.

Red was the lucky outcome. The director falls back to the old synth beds when a
track's stems will not load, so a slightly different mismatch would have merged
green and shipped the fallback. The director's tests now blank the manifest
when they inject fixture streams, because they are about director state. A
separate wiring test loads the real files through the default loader and
requires all ten tracks to come up on stems, with equal stem lengths and loops
that land on bar lines.

## A premise that was simply wrong

The manifest is a raw JSON file, and the working assumption was that an export
would leave it out unless the presets named it. The preset change was written
first and the check second.

The check, run against the unmodified presets, passed. Godot 4 treats JSON as a
resource and ships it. The preset change was reverted. The check stayed, with a
comment that says what it actually guards instead of what it was written to
prove.

## The stall that was a longer game

An 11,000-frame capture of the bot playing the campaign ended with it circling
the new Siege Tank. It looked like the bot could not win the fight.

A probe at simulation level said otherwise: victory on all three seeds, at
ticks 11,208, 12,163 and 11,471. The campaign used to end near tick 8,000. The
capture window had been sized for the old game and ran out mid-fight.

That would have been the end of it, except that every one of those bot runs
used god mode, and god mode refills grenades. The Siege Tank only takes
grenades and rockets from the front. With god mode off and no grenades in hand,
the same bot never killed it: 200 seconds, 8 deaths, hull at 8 of 80. The arena
crate now re-arms 180 ticks after nobody is holding a grenade, and that run
ends at 39.9 seconds.

So the stall on screen was not real, and the real one could not appear on
screen.

## Checksums that moved for a reason nobody had written down

The weapons package recorded "campaign golden untouched", and on its own tree
that was true. The scripted torture run never got far enough to roll a rare
weapon capsule. With the fairness changes merged, it does. Sample 5 of 6 moved.

A bisect over the picked commits cleared fairness, economy and the gunship one
at a time, which names a meeting point and not a cause. For the cause, both
weapons were forced out of the drop table in a scratch worktree, and all six
pre-merge samples came back byte for byte. A probe then put the first capsule
at tick 3,072, in a player's hands at 3,073. Samples are taken every 600 ticks,
so sample 5 had to move and samples 0 to 4 had to stay, which is what they did.
That arithmetic is in the re-record note.

## The one that was just carelessness

The version bump to 1.5.0 was committed and pushed with a red module in the
output directly above the commit line. Ten fixture tests held "1.4.4" as a
literal. The check and the commit were joined by a semicolon, so the commit ran
whatever the check said.

The fixture reads the version from `project.godot` now. The commit after it
says what happened.

## What is still unproven

The full suite and a local mirror of the blocking CI jobs are green on Linux.
The three-platform determinism run has not happened for this version, so the
goldens are confirmed on one architecture only. And the score has been measured
for loudness, peaks, loop seams and key, but nobody has listened to it.
