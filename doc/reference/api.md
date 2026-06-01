# API Reference

Every public type exported from `package:elo_engine/elo_engine.dart`.
Use this page as a lookup — narrative-style explanations live in the
[tutorial](../tutorial/getting-started.md) and
[how-to](../how-to/) sections.

## `EloEngine`

The main entry point. Holds mutable `EloItem` instances — `MatchResult`
and `MatchProposal` return live references that reflect subsequent
matches. Not thread-safe.

**Constructor**

```dart
EloEngine({
  required List<EloItem> items,
  List<EloMatch>? history,
  EloConfig? config,
})
```

Throws `ArgumentError` if any two items share the same `id`. If
`history` is provided, all matches are replayed in order before the
engine is ready.

**Static factory**

```dart
static EloEngine fromJson(Map<String, dynamic> json, {bool skipReplay = false})
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `json` | `Map<String, dynamic>` | Map produced by `toJson()`. |
| `skipReplay` | `bool` | If `true`, stored ratings are used as-is instead of replaying history. Faster for long sessions. |

**Fields and methods**

| Member | Type | Description |
|--------|------|-------------|
| `rankings` | `List<EloItem>` | Current ranking, highest-rated first. |
| `isConverged` | `bool` | Whether the ranking has stabilised (see `EloConfig`). |
| `record(idA, idB, outcome)` | `MatchResult` | Record a comparison outcome and update all ratings immediately. Throws `ArgumentError` for unknown IDs. Accepts raw IDs (not a `MatchProposal`) so you can record any pair, not just the one suggested by `nextMatch()`. |
| `nextMatch()` | `MatchProposal?` | Suggest the most informative next pair. Returns `null` when converged or when fewer than 2 items exist. |
| `undo()` | `void` | Remove the last match and recalculate all state from history. No-op on empty history. |
| `compareAlgorithms()` | `RankingComparison` | Run the full 15-algorithm ensemble and return synthesis results. |
| `toJson()` | `Map<String, dynamic>` | Serialise full state including history, ratings, and Glicko-2/TrueSkill snapshots. Schema version `1`. |

---

## `EloItem`

Represents one item being ranked. Mutable — ratings update in place.

**Constructor**

```dart
EloItem({
  required String id,
  double rating = 1200.0,
  int matchCount = 0,
  DateTime? lastSeen,
})
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique identifier. Must be unique within an `EloEngine`. |
| `rating` | `double` | Current ELO rating. Starts at `1200` by default. |
| `matchCount` | `int` | Number of non-skip matches this item has participated in. |
| `lastSeen` | `DateTime?` | Timestamp of the most recent non-skip match, or `null`. |

---

## `MatchOutcome`

```dart
enum MatchOutcome { aWins, bWins, tie, skip }
```

| Value | Meaning |
|-------|---------|
| `aWins` | Item A is preferred. |
| `bWins` | Item B is preferred. |
| `tie` | Both items are equally preferred. Applied as score 0.5 for each. |
| `skip` | The user skips this pair. No rating change; pair is suppressed for a few rounds. |

---

## `MatchProposal`

Returned by `EloEngine.nextMatch()`. Contains live references to engine
items.

| Field | Type | Description |
|-------|------|-------------|
| `itemA` | `EloItem` | First item in the proposed comparison. |
| `itemB` | `EloItem` | Second item in the proposed comparison. |
| `expectedA` | `double` | Expected score for A (0.0–1.0). Values near 0.5 indicate the most informative comparisons. |

---

## `MatchResult`

Returned by `EloEngine.record()`. Contains live references to engine
items — their ratings will reflect any subsequent matches.

| Field | Type | Description |
|-------|------|-------------|
| `itemA` | `EloItem` | First item (live reference). |
| `itemB` | `EloItem` | Second item (live reference). |
| `deltaA` | `double` | Rating change applied to item A in this match (positive = gained, negative = lost). |

---

## `EloConfig`

Controls ranking behaviour. Pass to `EloEngine(config:)`.

**Constructor**

```dart
const EloConfig({
  int startingRating = 1200,
  Map<int, int> kFactorStages = const {0: 64, 10: 32, 30: 16},
  int convergenceWindow = 5,
  double convergenceTau = 0.95,
  int minMatchesBeforeConverge = -1,
  bool allowTies = true,
  Set<AlgorithmId>? enabledAlgorithms,
})
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `startingRating` | `int` | `1200` | Initial rating for every new item. |
| `kFactorStages` | `Map<int, int>` | `{0:64, 10:32, 30:16}` | K-factor by match count threshold. Keys are match-count thresholds; values are K. |
| `convergenceWindow` | `int` | `5` | Compare current ranking to ranking this many matches ago when computing tau. |
| `convergenceTau` | `double` | `0.95` | Minimum Kendall's tau required for five consecutive windows to trigger convergence. |
| `minMatchesBeforeConverge` | `int` | `-1` | Minimum non-skip matches before convergence is possible. Any non-positive value uses `max(N, 20)` dynamically. Positive values set an explicit floor. |
| `allowTies` | `bool` | `true` | When `false`, `record()` throws `ArgumentError` on `MatchOutcome.tie`. Historical ties already in `history`/JSON are trusted on restore — this flag only gates new matches going forward. |
| `enabledAlgorithms` | `Set<AlgorithmId>?` | `null` | Which algorithms to compute. `null` runs all 15. A non-empty subset skips unwanted algorithms: disabled entries appear as `null` in `RankingComparison` and are excluded from `consensusRanking`, `interAlgorithmKendallTau`, and `divergences`. Disabling `glicko2` or `trueskill` also skips their per-match state updates inside `record` — real CPU savings, not just output filtering. An empty set throws `ArgumentError`. See [How-to: pick a subset of algorithms](../how-to/pick-algorithm-subset.md). |

---

## `RankingComparison`

Returned by `EloEngine.compareAlgorithms()`. Every algorithm field is
nullable. A field is non-null only for algorithms that were enabled via
`EloConfig.enabledAlgorithms` (or all of them when that config is
`null`, which is the default). Always null-check before use.

| Field | Type | Description |
|-------|------|-------------|
| `eloRanking` | `List<EloItem>?` | Ranking by ELO rating. |
| `glicko2Ranking` | `List<EloItem>?` | Ranking by Glicko-2 display rating. |
| `trueskillRanking` | `List<EloItem>?` | Ranking by TrueSkill conservative score (μ − 3σ). |
| `bradleyTerryRanking` | `List<EloItem>?` | Ranking by Bradley-Terry model. |
| `thurstoneRanking` | `List<EloItem>?` | Ranking by Thurstone Case V model. |
| `springRankRanking` | `List<EloItem>?` | Ranking by SpringRank. |
| `bordaRanking` | `List<EloItem>?` | Ranking by Borda count. |
| `copelandRanking` | `List<EloItem>?` | Ranking by Copeland score. |
| `pageRankRanking` | `List<EloItem>?` | Ranking by PageRank on win graph. |
| `markovRanking` | `List<EloItem>?` | Ranking by Markov chain stationary distribution. |
| `schulzeRanking` | `List<EloItem>?` | Ranking by Schulze (beat-path) method. |
| `rankedPairsRanking` | `List<EloItem>?` | Ranking by Ranked Pairs (Tideman) method. |
| `hodge` | `HodgeResult?` | Hodge decomposition output. |
| `serialRank` | `SerialRankResult?` | SerialRank output. |
| `matrixFactorization` | `MatrixFactorizationResult?` | Matrix factorization output. |
| `consensusRanking` | `List<EloItem>` | Harmonic mean consensus across all active rankings. Always non-null. |
| `interAlgorithmKendallTau` | `double` | Average pairwise Kendall's tau across all active rankings. 1.0 = perfect agreement. |
| `divergences` | `List<AlgorithmDivergence>` | Per-item rank spread across all active algorithms. |

---

## `AlgorithmDivergence`

One entry per item in `RankingComparison.divergences`. Describes how
much the algorithms disagree on where this item ranks.

| Field | Type | Description |
|-------|------|-------------|
| `item` | `EloItem` | The item. |
| `rankByAlgorithm` | `Map<AlgorithmId, int>` | 0-indexed rank for this item in each algorithm (0 = highest-ranked). |
| `rankSpread` | `int` | `max(ranks) − min(ranks)`. 0 = all algorithms agree; larger = more disagreement. |

---

## `HodgeResult`

Output of the HodgeRank algorithm within `RankingComparison.hodge`.

| Field | Type | Description |
|-------|------|-------------|
| `gradientRanking` | `List<EloItem>` | Items sorted by the gradient component of the Hodge decomposition, highest first. |
| `cyclicMagnitude` | `double` | Fraction of total preference flow that is cyclic (non-transitive). Range 0–1. |
| `harmonicMagnitude` | `double` | Fraction of preference flow that is harmonic (inconsistent but non-cyclic). Range 0–1. |

See [HodgeRank explanation](../explanation/algorithms/hodge.md) for the
full decomposition.

---

## `SerialRankResult`

Output of the SerialRank algorithm within `RankingComparison.serialRank`.

| Field | Type | Description |
|-------|------|-------------|
| `ranking` | `List<EloItem>` | Items sorted by SerialRank score, highest first. |
| `rankability` | `double` | 1.0 = perfectly rankable; small values indicate multi-dimensional preferences. |

---

## `MatrixFactorizationResult`

Output of the matrix factorization algorithm within
`RankingComparison.matrixFactorization`.

| Field | Type | Description |
|-------|------|-------------|
| `bestRank` | `int` | The rank of the factorization that best fits the data. |
| `explainedVariance` | `double` | Fraction of variance in the comparison matrix explained by the factorization. |
| `consensusRanking` | `List<EloItem>` | Items sorted by the latent score from the factorization, highest first. |

---

## `AlgorithmId`

Enum identifying each algorithm. Used as keys in
`AlgorithmDivergence.rankByAlgorithm`.

| Value | Algorithm |
|-------|-----------|
| `AlgorithmId.elo` | ELO |
| `AlgorithmId.glicko2` | Glicko-2 |
| `AlgorithmId.trueskill` | TrueSkill |
| `AlgorithmId.bradleyTerry` | Bradley-Terry |
| `AlgorithmId.thurstone` | Thurstone |
| `AlgorithmId.springRank` | SpringRank |
| `AlgorithmId.pageRank` | PageRank |
| `AlgorithmId.markov` | Markov chain |
| `AlgorithmId.copeland` | Copeland |
| `AlgorithmId.schulze` | Schulze |
| `AlgorithmId.rankedPairs` | Ranked Pairs |
| `AlgorithmId.borda` | Borda |
| `AlgorithmId.hodge` | HodgeRank |
| `AlgorithmId.serialRank` | SerialRank |
| `AlgorithmId.matrixFactorization` | Matrix Factorization |

Each value links to a dedicated explanation in
[doc/explanation/algorithms/](../explanation/algorithms/).
