# How-to — aggregate group decisions

When multiple people rank the same pool of items, collect each person's
votes into the same engine and use `compareAlgorithms()` to synthesise a
consensus.

```dart
import 'package:elo_engine/elo_engine.dart';

// One shared engine for all voters.
final engine = EloEngine(
  items: destinations.map((d) => EloItem(id: d)).toList(),
);

// Alice votes.
for (final (a, b, outcome) in aliceVotes) {
  engine.record(a, b, outcome);
}

// Bob votes.
for (final (a, b, outcome) in bobVotes) {
  engine.record(a, b, outcome);
}

// Synthesise.
final comparison = engine.compareAlgorithms();

print('Consensus ranking:');
for (final item in comparison.consensusRanking) {
  print('  ${item.id}');
}

final tau = comparison.interAlgorithmKendallTau;
print('Inter-algorithm agreement (Kendall τ): ${tau.toStringAsFixed(3)}');

// Items most disputed across algorithms.
final disputed = comparison.divergences
  ..sort((a, b) => b.rankSpread.compareTo(a.rankSpread));
for (final d in disputed.take(3)) {
  print('  ${d.item.id}  spread=${d.rankSpread}  '
        'ranks by algorithm: ${d.rankByAlgorithm}');
}
```

## Interpreting `interAlgorithmKendallTau`

| Value | Meaning |
|-------|---------|
| > 0.9 | All algorithms agree — ranking is robust and trustworthy. |
| 0.6–0.9 | Moderate agreement — middle positions have genuine ambiguity. |
| < 0.6 | Low agreement — preferences may be cyclic or multi-dimensional. |

**Tip:** When `interAlgorithmKendallTau` is low, check
`comparison.hodge?.cyclicMagnitude`. A high value (above ~0.4) means that
a significant fraction of preference flow is non-transitive — e.g. Alice
> Bob > Carol > Alice. No single ranking can fully represent cyclic
preferences, and the ensemble consensus is the best available
approximation.

## See also

- [How-to: merge independent rankings](merge-independent-rankings.md) —
  for when each voter must rank privately without seeing the others.
- [HodgeRank explanation](../explanation/algorithms/hodge.md) — the math
  behind `cyclicMagnitude` and `harmonicMagnitude`.
