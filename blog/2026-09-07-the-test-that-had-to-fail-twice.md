# The test that had to fail twice

*2026-09-07*

The useful turn in this export pass was not getting three builds out of Godot.
It was narrowing what each passing check could honestly mean.

The immediate change was small: a solo player holding ready in Endless mode
needed to see the same sort of progress feedback that co-op players could see.
The new exports needed to contain that repair. Loading textures and advancing
Campaign did not answer that question, even when both checks passed.

So the external pack inspector grew a specific check: start the packed game's
Endless intermission, hold ready, require visible progress in its feedback state,
then release and require that state to clear.

## The first red result belonged to the test

The initial attempt failed before it established anything about the repair:

```text
Invalid assignment of property or key '_last_inputs' with value of type 'Array'
```

The inspector had supplied an untyped array to the packed game's typed input
array. This was a harness error, not evidence that the exported gameplay was
broken. The subsequent deadline failure was not a second independent game bug.

The correction preserved the existing typed array and appended an input instance
constructed from the script loaded from that pack. The failed log stayed in
place. It was not renamed into passing evidence.

The corrected inspector then reported:

```text
EXPORT READY PASS: packed solo hold shows progress and release clears it
```

That was useful, but incomplete. A test that only passes the new build has not
yet shown that it distinguishes the change we care about.

## The second red result was the point

The same corrected inspector was run against the earlier pack. This time the
failure described the missing behavior:

```text
EXPORT RUNTIME FAIL: packed solo ready-up feedback is missing or does not cancel
```

The old pack failed; the repaired pack passed. That establishes a particular
behavioral difference. It does not establish that every source change is present,
or that the game is ready for release.

The three targets had identical game-pack hashes. That established identical
packed bytes across them. It did not establish native execution on three
operating systems.

## Offline is a property of the startup path

There was another boundary to make explicit. The game's Steam bridge calls
`steamInitEx` from its constructor when the native singleton exists. Loading the
game in a Steam-enabled engine is therefore not a neutral offline inspection.

The pack inspector now rejects that engine before loading the game. A separate,
tiny inspection pack checks the exact copied release executable without starting
the game or initializing Steam. It found 22 required method names and five signal
names. Those are binding-presence checks, not proof of account behavior.

The result is three distinct questions: does the pack contain the repair, does
the shipped executable expose the bindings, and does the game work with the
intended live account? The first two have evidence here. The third remains open.

That separation is the progress worth keeping. More green checks would not have
helped if they kept answering a different question.

Evidence and reproduction details are in
[the candidate validation report](../docs/steam-candidate-validation.md).
The frozen package remains a review candidate, not a published or approved release.
