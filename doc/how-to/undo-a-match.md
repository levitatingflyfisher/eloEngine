# How-to — undo a match

```dart
// Record a match.
engine.record('Oliver', 'Milo', MatchOutcome.aWins);

// Oops — wrong button. Undo restores full state.
engine.undo();

// You can undo multiple times, back to an empty history.
engine.undo();
engine.undo();
```

`undo()` pops the last `EloMatch` from the history and replays all
remaining matches from scratch. Ratings, match counts, Glicko-2 state,
TrueSkill state, and convergence tracking are all reset and
recalculated. If the history is already empty, `undo()` is a no-op.

The cost is O(history × items) per call because the entire history is
replayed. For short sessions this is imperceptible; for sessions with
hundreds of matches you may prefer to limit how deep the undo chain can
go in your UI, or keep a periodic JSON checkpoint so users can roll back
to a known-good state without replaying everything.
