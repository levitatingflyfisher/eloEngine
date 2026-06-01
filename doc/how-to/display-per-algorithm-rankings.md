# How-to — display per-algorithm rankings

`compareAlgorithms()` returns a `divergences` list where each entry holds
every item's rank in every algorithm. This is the right data source for a
multi-column rankings table or a color-coded grid where you can see at a
glance where a specific item lands across all 15 algorithms.

```dart
final c = engine.compareAlgorithms();

// Build a table: rows = items (by consensus rank), columns = algorithms.
for (final div in c.divergences) {
  final consensusRank = c.consensusRanking.indexOf(div.item) + 1;
  final perAlgo = AlgorithmId.values.map((id) {
    final rank = div.rankByAlgorithm[id]; // null if algorithm had no result
    return rank != null ? '${rank + 1}' : '-';
  }).join('  ');
  print('${div.item.id.padRight(12)} consensus=$consensusRank  $perAlgo');
}
```

`rankByAlgorithm` values are 0-indexed (0 = top-ranked). Add 1 for
display.

## Color-coding by distance from consensus

```dart
Color rankColor(AlgorithmDivergence div, AlgorithmId algo, int consensusRank) {
  final rank = div.rankByAlgorithm[algo];
  if (rank == null) return Colors.grey;
  final distance = (rank - (consensusRank - 1)).abs();
  if (distance == 0) return Colors.green;
  if (distance <= 1) return Colors.yellow;
  return Colors.red;
}
```

`AlgorithmId.values` enumerates all 15 algorithm IDs in definition order
— use it to drive column headers.
