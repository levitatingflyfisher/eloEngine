# How-to — pick a subset of algorithms

By default the engine runs all 15 algorithms inside `compareAlgorithms()`
and maintains Glicko-2 and TrueSkill state on every `record()` call. That
is the right default for a power-user or research tool where you want the
full ensemble and the cross-algorithm disagreement signal. It is *not*
the right default for a phone app that just needs a good ranking fast.

Pass `enabledAlgorithms` to trim the ensemble:

```dart
final engine = EloEngine(
  items: names.map((n) => EloItem(id: n)).toList(),
  config: const EloConfig(
    enabledAlgorithms: {
      AlgorithmId.elo,      // cheap, always available
      AlgorithmId.borda,    // good consensus-building signal
      AlgorithmId.copeland, // robust to intransitive preferences
    },
  ),
);
```

## What changes when you do this

- **Disabled algorithms appear as `null`** in the `RankingComparison`
  returned by `compareAlgorithms()`. Null-check before use.
- **Consensus, Kendall's tau, and divergences aggregate only over what
  ran.** A single-algorithm subset produces `consensusRanking ==
  eloRanking` and `interAlgorithmKendallTau == 1.0`.
- **Glicko-2 and TrueSkill stop updating their per-match state inside
  `record()`** when disabled. That is where the actual CPU win lives —
  not in the once-per-session `compareAlgorithms()` call, but in the hot
  path where the user is tapping.
- **The pairwise matrix is skipped entirely** when no batch algorithm is
  enabled. An online-only pipeline (`{elo, glicko2, trueskill}`) does
  zero batch work.
- `null` (the default) runs everything. An empty set throws
  `ArgumentError` — it is almost certainly a bug.

## When to restrict

| Goal | Suggested subset |
|------|------------------|
| Phone app, minimum CPU | `{elo}` or `{elo, borda}` |
| Good consensus without the expensive batch stuff | `{elo, glicko2, borda, copeland}` |
| Avoid the graph decomposition algorithms (Hodge / SerialRank / MatrixFactorization) | All *except* those three |
| Research / cross-algorithm divergence analysis | `null` (all 15) |

The ELO rating field on every `EloItem` is always maintained regardless
of this setting — `record()` updates it in place, and `rankings` keeps
working. "Disabling ELO" only removes it from `compareAlgorithms()`
output; it does not stop the engine from tracking ratings.

The `enabledAlgorithms` set is included in `EloEngine.toJson()` via
`EloConfig` and survives a round-trip through `fromJson`, so a persisted
session resumes with the same algorithms on or off.

## See also

- [Choosing an algorithm](../explanation/choosing-an-algorithm.md) — a
  decision guide covering all 15 algorithms and their tradeoffs.
