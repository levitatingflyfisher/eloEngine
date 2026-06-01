# Tutorial — rank a list from scratch

This tutorial walks through ranking eight baby names by asking a person to
pick between pairs. By the end you will have a stable ranking, know how to
read it, undo a mistake, and save the session to disk.

## Step 1 — Create the engine

```dart
import 'package:elo_engine/elo_engine.dart';

final names = [
  'Oliver', 'Eliot', 'Milo', 'Leo',
  'Isla', 'Aurora', 'Maeve', 'Phoebe',
];

final engine = EloEngine(
  items: names.map((n) => EloItem(id: n)).toList(),
);
```

Every item starts at `rating = 1200` (the default `startingRating` in
`EloConfig`). This is an arbitrary reference point — only differences
between ratings matter.

## Step 2 — Run the comparison loop

```dart
import 'dart:io'; // for stdin.readLineSync

while (!engine.isConverged) {
  final match = engine.nextMatch();
  if (match == null) break; // fewer than 2 items, or already converged

  // Present the pair to the user however your UI requires.
  // match.expectedA is the probability (0–1) that A is preferred.
  // Values near 0.5 mean the engine is genuinely uncertain — most informative.
  print('Which do you prefer?');
  print('  1. ${match.itemA.id}');
  print('  2. ${match.itemB.id}');

  final choice = stdin.readLineSync();
  final outcome = choice == '1' ? MatchOutcome.aWins : MatchOutcome.bWins;
  engine.record(match.itemA.id, match.itemB.id, outcome);
}
```

`nextMatch()` selects the pair that will provide the most information: it
favors uncertain items (few matches), close matchups (expected score near
0.5), and avoids re-proposing pairs seen recently. It returns `null` when
the engine has converged or when there are fewer than two items.

`isConverged` becomes `true` when Kendall's tau between the current
ranking and the ranking `convergenceWindow` matches ago has stayed above
`convergenceTau` for five consecutive matches. The defaults require
roughly 20–30 comparisons for 8 items.

## Step 3 — Read the rankings

```dart
print('\nFinal rankings:');
for (final item in engine.rankings) {
  print('  ${item.id}  '
        'rating=${item.rating.round()}  '
        'matches=${item.matchCount}');
}
```

`engine.rankings` always returns items sorted highest-rated first.
`matchCount` tells you how many non-skip comparisons each item has
participated in.

## Step 4 — Undo a mistake

```dart
// The last recorded match is removed and all ratings are recalculated.
engine.undo();
```

`undo()` removes the most recent entry from the match history and replays
the entire history from scratch. This is O(history × items) but is correct
for any depth of undo chain. It also works after a `fromJson` restore —
the full history is always stored.

## Step 5 — Persist the session

```dart
import 'dart:convert';
import 'dart:io';

// Save
final json = jsonEncode(engine.toJson());
File('session.json').writeAsStringSync(json);

// Restore and replay from scratch (always correct)
final restored = EloEngine.fromJson(
  jsonDecode(File('session.json').readAsStringSync()),
);

// Restore fast, trusting stored ratings (use for history > ~500 matches)
final fast = EloEngine.fromJson(
  jsonDecode(File('session.json').readAsStringSync()),
  skipReplay: true,
);
```

The JSON schema is versioned (`"version": 1`). With `skipReplay: false`
(the default), all ratings are recalculated from the stored match history
— ideal for correctness. With `skipReplay: true`, stored ratings are
trusted directly, which is much faster for long sessions.

## Next steps

- [How-to guides](../how-to/) — save/restore, group voting, merge
  independent rankings, subset selection, and more.
- [API reference](../reference/api.md) — every public type and method.
- [Choosing an algorithm](../explanation/choosing-an-algorithm.md) — when
  each of the 15 algorithms earns its keep.
