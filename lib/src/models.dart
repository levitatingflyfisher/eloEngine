/// Identifies each ranking algorithm. Used in [EloConfig.enabledAlgorithms],
/// [AlgorithmDivergence], and [RankingComparison].
enum AlgorithmId {
  /// Classic ELO rating system. Online, single-scalar, K-factor decay.
  elo,

  /// Glicko-2: ELO + rating deviation + volatility. Online.
  glicko2,

  /// Bradley-Terry maximum-likelihood model. Batch.
  bradleyTerry,

  /// Microsoft's TrueSkill (two-player form). Online, Gaussian skill+sigma.
  trueskill,

  /// Thurstonian Case V (probit) model. Batch.
  thurstone,

  /// SpringRank: hierarchy recovery via a linear system of springs. Batch.
  springRank,

  /// PageRank over the pairwise win graph. Batch.
  pageRank,

  /// Stationary distribution of a row-stochastic Markov chain. Batch.
  markov,

  /// Copeland's method: rank by (wins − losses) against other items. Batch.
  copeland,

  /// Schulze method (beatpath winner). Batch.
  schulze,

  /// Ranked Pairs (Tideman). Batch.
  rankedPairs,

  /// Borda count. Batch.
  borda,

  /// HodgeRank: least-squares gradient of pairwise log-odds. Batch.
  hodge,

  /// SerialRank: seriation on the pairwise matrix. Batch.
  serialRank,

  /// Non-negative matrix factorization of the win matrix. Batch.
  matrixFactorization,
}

/// A single item being ranked. Mutable — the engine updates [rating],
/// [matchCount], and [lastSeen] in place as matches are recorded.
class EloItem {
  /// Stable identifier. Must be unique within an [EloEngine].
  final String id;

  /// Current ELO rating. Defaults to [EloConfig.startingRating] at
  /// construction, then mutated by the engine on every match.
  double rating;

  /// Number of matches this item has participated in (wins, losses, ties;
  /// skipped proposals are not counted).
  int matchCount;

  /// Wall-clock timestamp of the item's most recent match, or `null` if it
  /// has never played. Used by [EloEngine.nextMatch] for recency penalties.
  DateTime? lastSeen;

  /// Constructs an item. Only [id] is required; the engine fills in the
  /// rest, so consumers typically pass just `EloItem(id: 'foo')`.
  EloItem({
    required this.id,
    this.rating = 1200.0,
    this.matchCount = 0,
    this.lastSeen,
  });

  /// Serializes this item to a JSON-compatible map. Round-trips via
  /// [EloItem.fromJson].
  Map<String, dynamic> toJson() => {
        'id': id,
        'rating': rating,
        'matchCount': matchCount,
        if (lastSeen != null)
          // Unix seconds (second-granularity is intentional per PRD §10 JSON schema)
          'lastSeen': lastSeen!.millisecondsSinceEpoch ~/ 1000,
      };

  /// Restores an item from its [toJson] representation.
  factory EloItem.fromJson(Map<String, dynamic> j) => EloItem(
        id: j['id'] as String,
        rating: (j['rating'] as num).toDouble(),
        matchCount: j['matchCount'] as int,
        lastSeen: j['lastSeen'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (j['lastSeen'] as int) * 1000)
            : null,
      );
}

/// The outcome of a pairwise comparison, from the perspective of `itemA`.
enum MatchOutcome {
  /// Item A won.
  aWins,

  /// Item B won.
  bWins,

  /// Draw. Rejected by [EloEngine.record] if [EloConfig.allowTies] is false.
  tie,

  /// Skip this pair without recording a result. The engine suppresses the
  /// pair for a few rounds but does not mutate ratings or match counts.
  skip,
}

/// An immutable record of one comparison. [EloEngine] retains these in
/// history for replay, convergence checks, and batch-algorithm recomputation.
class EloMatch {
  /// Identifier of the first item.
  final String idA;

  /// Identifier of the second item.
  final String idB;

  /// Outcome from A's perspective. [MatchOutcome.skip] is never persisted.
  final MatchOutcome outcome;

  /// Wall-clock time the match was recorded.
  final DateTime timestamp;

  /// Constructs a match record. Prefer [EloEngine.record] over building
  /// these by hand unless you are restoring history.
  const EloMatch({
    required this.idA,
    required this.idB,
    required this.outcome,
    required this.timestamp,
  });

  /// Serializes to a JSON-compatible map. Round-trips via [EloMatch.fromJson].
  Map<String, dynamic> toJson() => {
        'idA': idA,
        'idB': idB,
        'outcome': outcome.name,
        // Unix seconds (second-granularity is intentional per PRD §10 JSON schema)
        'ts': timestamp.millisecondsSinceEpoch ~/ 1000,
      };

  /// Restores a match from its [toJson] representation.
  factory EloMatch.fromJson(Map<String, dynamic> j) => EloMatch(
        idA: j['idA'] as String,
        idB: j['idB'] as String,
        outcome: MatchOutcome.values.byName(j['outcome'] as String),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (j['ts'] as int) * 1000),
      );
}

/// Immutable engine configuration. All fields have sensible defaults; a
/// bare `EloConfig()` is a good starting point.
class EloConfig {
  /// Initial rating assigned to new items. 1200 is the ELO convention.
  final int startingRating;

  /// K-factor schedule as `{matchCount threshold: K}`. The engine picks the
  /// largest threshold ≤ the item's current `matchCount`. Default mirrors
  /// FIDE: high K early, decaying as an item stabilizes.
  final Map<int, int> kFactorStages;

  /// Number of recent matches inspected by [EloEngine.isConverged] when
  /// measuring rating stability.
  final int convergenceWindow;

  /// Convergence tolerance. The Kendall tau between the current ranking and
  /// the ranking [convergenceWindow] matches ago must meet or exceed this
  /// value for [EloEngine.isConverged] to return `true`.
  final double convergenceTau;

  /// Minimum match count required before convergence can be claimed.
  /// `-1` (default) means `max(N, 20)`, computed from item count at runtime.
  final int minMatchesBeforeConverge;

  /// When `false`, [EloEngine.record] rejects [MatchOutcome.tie] with an
  /// [ArgumentError]. Use this when the consumer should force a decision
  /// (e.g., a baby-name ranker where "they're equal" is not a useful
  /// signal). Historical ties already in `history`/JSON are trusted on
  /// restore — this flag only gates new matches going forward.
  final bool allowTies;

  /// Which algorithms the engine should compute.
  ///
  /// - `null` (default) → run all 15 algorithms.
  /// - non-empty `Set<AlgorithmId>` → run only the listed algorithms.
  ///   Disabled entries appear as `null` in [RankingComparison] and are
  ///   excluded from `consensusRanking`, `interAlgorithmKendallTau`, and
  ///   `divergences`. Disabling [AlgorithmId.glicko2] or
  ///   [AlgorithmId.trueskill] also skips their per-match state updates
  ///   inside [EloEngine.record], which is where the real perf win is.
  /// - `const {}` (empty set) → [ArgumentError] at engine construction.
  ///
  /// [AlgorithmId.elo] is always cheap (O(N log N) sort of in-memory
  /// ratings that `record` maintains anyway) but still respects this set
  /// for output purposes — disabling ELO hides `eloRanking` from
  /// [RankingComparison], it does not stop `record` from updating item
  /// ratings.
  final Set<AlgorithmId>? enabledAlgorithms;

  /// Constructs a config. All parameters are optional.
  const EloConfig({
    this.startingRating = 1200,
    this.kFactorStages = const {0: 64, 10: 32, 30: 16},
    this.convergenceWindow = 5,
    this.convergenceTau = 0.95,
    this.minMatchesBeforeConverge = -1,
    this.allowTies = true,
    this.enabledAlgorithms,
  });

  /// Serializes to a JSON-compatible map. Round-trips via [EloConfig.fromJson].
  Map<String, dynamic> toJson() => {
        'startingRating': startingRating,
        'kFactorStages':
            kFactorStages.map((k, v) => MapEntry(k.toString(), v)),
        'convergenceWindow': convergenceWindow,
        'convergenceTau': convergenceTau,
        'minMatchesBeforeConverge': minMatchesBeforeConverge,
        'allowTies': allowTies,
        if (enabledAlgorithms != null)
          'enabledAlgorithms':
              enabledAlgorithms!.map((a) => a.name).toList(),
      };

  /// Restores a config from its [toJson] representation. Missing fields
  /// fall back to defaults so older persisted JSON keeps round-tripping.
  factory EloConfig.fromJson(Map<String, dynamic> j) => EloConfig(
        startingRating: j['startingRating'] as int? ?? 1200,
        kFactorStages: j['kFactorStages'] != null
            ? (j['kFactorStages'] as Map<String, dynamic>)
                .map((k, v) => MapEntry(int.parse(k), v as int))
            : const {0: 64, 10: 32, 30: 16},
        convergenceWindow: j['convergenceWindow'] as int? ?? 5,
        convergenceTau: (j['convergenceTau'] as num?)?.toDouble() ?? 0.95,
        minMatchesBeforeConverge: j['minMatchesBeforeConverge'] as int? ?? -1,
        allowTies: j['allowTies'] as bool? ?? true,
        enabledAlgorithms: j['enabledAlgorithms'] != null
            ? (j['enabledAlgorithms'] as List<dynamic>)
                .map((e) => AlgorithmId.values.byName(e as String))
                .toSet()
            : null,
      );
}

/// Result of a single comparison. [itemA] and [itemB] are live references to
/// the engine's internal [EloItem] instances — their ratings will reflect
/// subsequent matches. Capture [deltaA] if you need the post-match delta.
class MatchResult {
  /// The first item, post-update. Live reference to engine state.
  final EloItem itemA;

  /// The second item, post-update. Live reference to engine state.
  final EloItem itemB;

  /// Rating change applied to [itemA] (B's delta is `-deltaA`).
  final double deltaA;

  /// Constructs a match result. Consumers receive these from
  /// [EloEngine.record] and rarely build them by hand.
  const MatchResult({
    required this.itemA,
    required this.itemB,
    required this.deltaA,
  });
}

/// A pair of items [EloEngine.nextMatch] wants compared next, along with the
/// expected ELO win probability for A.
class MatchProposal {
  /// First item in the proposed pair.
  final EloItem itemA;

  /// Second item in the proposed pair.
  final EloItem itemB;

  /// E_A: expected score for A (0.0–1.0). Closer to 0.5 = more informative.
  final double expectedA;

  /// Constructs a proposal. Typically built by [EloEngine.nextMatch].
  const MatchProposal({
    required this.itemA,
    required this.itemB,
    required this.expectedA,
  });
}
