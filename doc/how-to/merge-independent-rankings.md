# How-to — merge independent rankings

Use this when each participant must rank **privately** before the result
is revealed — couples picking a baby name, friends picking a restaurant
without anchoring on each other's votes. Each person builds their own
engine, and `EloMerge.combine` aggregates the snapshots.

```dart
import 'package:elo_engine/elo_engine.dart';

final names = ['eliot', 'james', 'oliver', 'henry', 'theodore'];

// Pass the phone to Alice. She does her matchups in private.
final alice = EloEngine(items: names.map((n) => EloItem(id: n)).toList());
while (!alice.isConverged) {
  final pair = alice.nextMatch();
  if (pair == null) break;
  alice.record(pair.itemA.id, pair.itemB.id, askAlice(pair));
}

// Pass the phone to Bob. Same flow, his own engine.
final bob = EloEngine(items: names.map((n) => EloItem(id: n)).toList());
while (!bob.isConverged) {
  final pair = bob.nextMatch();
  if (pair == null) break;
  bob.record(pair.itemA.id, pair.itemB.id, askBob(pair));
}

// Reveal: combine the snapshots.
final merged = EloMerge.combine([
  alice.snapshot(participantId: 'alice'),
  bob.snapshot(participantId: 'bob'),
]);

print('Merged ranking (harmonic mean — surfaces consensus):');
for (final r in merged) {
  final tag = r.agreement >= 0.75 ? '✓ both like' : r.agreement <= 0.25 ? '⚠ split' : '';
  print('  ${r.item.id.padRight(10)}  '
        'score=${r.combinedScore.toStringAsFixed(2)}  '
        'agreement=${r.agreement.toStringAsFixed(2)}  $tag');
}
```

## Choosing a merge strategy

| Strategy | When to use |
|---|---|
| `harmonicMean` (default) | Couples picking a baby name, friends picking a restaurant — surfaces names *both* people like and penalizes one-person favorites. The default for a reason. |
| `arithmeticMean` | Group decisions where one passionate vote should be allowed to lift a middling option (e.g. "anyone get to pick this week?"). |
| `minimum` | Strictest filter — final score is bounded by the worst rating any participant gave. Use when even one veto should drop an item. |

## Why the default is harmonic mean

Suppose Alice ranks **Eliot** #1 and Bob ranks it #45 out of 50.

- **Arithmetic mean** scores Eliot at the midpoint (#23) — false
  consensus from one enthusiastic partner.
- **Harmonic mean** pulls the score toward the worse end (~#38) —
  surfaces that Bob doesn't like it.
- **Minimum** scores Eliot at #45 — Bob's veto wins outright.

Harmonic mean is the right balance: it respects strong feelings on both
sides without letting one outlier dominate.

## What `agreement` tells you

| Value | Interpretation |
|---|---|
| `1.0` | Both participants gave this item the same rank. |
| `> 0.75` | Within a few positions of each other — solid agreement. |
| `0.25–0.75` | Mixed — worth talking about. |
| `< 0.25` | Sharp disagreement — one loves it, the other doesn't. |
| `0.0` | One ranked it #1, the other ranked it last. |

`agreement` is per-item, not per-session — sort by it to find the
*talk-about* items.
