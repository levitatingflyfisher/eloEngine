# How-to — configure convergence

The default settings are conservative. For a quick session (e.g. 10
items, single user, "good enough" ranking), this config roughly halves
the number of comparisons:

```dart
final engine = EloEngine(
  items: items,
  config: const EloConfig(
    convergenceTau: 0.85,        // less strict stability (default: 0.95)
    minMatchesBeforeConverge: 15, // explicit floor instead of max(N, 20)
  ),
);
```

For a slower, more robust ranking (large item sets, multiple voters,
high-stakes decisions):

```dart
final engine = EloEngine(
  items: items,
  config: const EloConfig(
    convergenceTau: 0.98,
    convergenceWindow: 8,
    minMatchesBeforeConverge: 40,
  ),
);
```

- **`convergenceTau`** — Kendall's tau threshold. Raise it (toward 1.0)
  for a more stable but slower-converging ranking. Lower it for faster
  convergence with more residual uncertainty.
- **`convergenceWindow`** — how many matches back to compare the current
  ranking to. A larger window detects slower drift but takes longer to
  trigger convergence.
- **`minMatchesBeforeConverge`** — hard floor on the number of non-skip
  matches before `isConverged` can become `true`. Any non-positive value
  (including the default `-1`) uses `max(N, 20)` dynamically. Only
  positive values set an explicit floor.
- **`kFactorStages`** — controls how aggressively ratings shift per
  match. The default `{0: 64, 10: 32, 30: 16}` means: K=64 for the first
  10 matches, K=32 from match 10–29, K=16 from match 30 onward. Increase
  K for faster early movement; decrease it to stabilize established
  ratings.
- **`allowTies`** — when `false`, `record()` throws `ArgumentError` if
  you pass `MatchOutcome.tie`. Historical ties already present in
  `history` or a restored JSON snapshot are trusted; this flag only
  gates new matches going forward. Leave it at the default (`true`)
  unless your UI needs to force the user to pick a winner.

**Tip:** If your items fall into categories that resist cross-category
comparison (e.g. boy names vs girl names), create a separate `EloEngine`
per category. Forcing cross-category comparisons inflates cyclic flow
and causes the engine to ask many more questions before converging.
