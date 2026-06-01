import 'models.dart';

/// Per-item rank spread across all non-null algorithms in a [RankingComparison].
class AlgorithmDivergence {
  /// The item whose rank is being compared across algorithms.
  final EloItem item;

  /// 0-indexed rank of this item in each algorithm (0 = highest-ranked).
  final Map<AlgorithmId, int> rankByAlgorithm;

  /// max(ranks) − min(ranks). 0 = perfect agreement; larger = more disagreement.
  final int rankSpread;

  /// Constructs a divergence entry.
  const AlgorithmDivergence({
    required this.item,
    required this.rankByAlgorithm,
    required this.rankSpread,
  });
}

// ── Deep-batch result types ───────────────────────────────────────────────────

/// Hodge decomposition output from [RankingComparison.hodge].
class HodgeResult {
  /// Ranking derived from the gradient component of the flow decomposition.
  final List<EloItem> gradientRanking;

  /// Magnitude of the cyclic component (rock-paper-scissors preference loops).
  /// Large values mean the data resists a consistent linear order.
  final double cyclicMagnitude;

  /// Magnitude of the harmonic component (residual after gradient+cyclic).
  /// Large values mean the preference graph has non-trivial topology.
  final double harmonicMagnitude;

  /// Constructs a HodgeRank result.
  const HodgeResult({
    required this.gradientRanking,
    required this.cyclicMagnitude,
    required this.harmonicMagnitude,
  });
}

/// SerialRank output from [RankingComparison.serialRank].
class SerialRankResult {
  /// Items ordered by the leading Fiedler vector of the pairwise matrix.
  final List<EloItem> ranking;

  /// 1.0 = perfectly rankable; small value = multidimensional preferences.
  final double rankability;

  /// Constructs a SerialRank result.
  const SerialRankResult({required this.ranking, required this.rankability});
}

/// Matrix factorization output from [RankingComparison.matrixFactorization].
class MatrixFactorizationResult {
  /// Best rank-k approximation that explained the win matrix (1 ≤ k ≤ 5).
  /// Rank 1 indicates one skill dimension dominates.
  final int bestRank;

  /// Fraction of Frobenius norm explained by the rank-k approximation.
  final double explainedVariance;

  /// Ranking aggregated from the leading latent factor(s).
  final List<EloItem> consensusRanking;

  /// Constructs a matrix-factorization result.
  const MatrixFactorizationResult({
    required this.bestRank,
    required this.explainedVariance,
    required this.consensusRanking,
  });
}

// ── Primary output type ───────────────────────────────────────────────────────

/// Full ensemble output from [EloEngine.compareAlgorithms()].
///
/// Every algorithm field is nullable. Fields are non-null only for
/// algorithms that were enabled via [EloConfig.enabledAlgorithms] (or all
/// of them when that config is `null`, which is the default). Always
/// null-check before use.
class RankingComparison {
  // Online algorithms
  /// Ranking from the classic ELO score, or `null` if ELO was disabled.
  final List<EloItem>? eloRanking;

  /// Ranking from Glicko-2 conservative skill, or `null` if disabled.
  final List<EloItem>? glicko2Ranking;

  // Batch vote-counting algorithms
  /// PageRank over the win graph, or `null` if disabled.
  final List<EloItem>? pageRankRanking;

  /// Stationary Markov-chain ranking, or `null` if disabled.
  final List<EloItem>? markovRanking;

  /// Copeland (wins − losses) ranking, or `null` if disabled.
  final List<EloItem>? copelandRanking;

  /// Schulze beatpath ranking, or `null` if disabled.
  final List<EloItem>? schulzeRanking;

  /// Ranked Pairs (Tideman) ranking, or `null` if disabled.
  final List<EloItem>? rankedPairsRanking;

  /// Borda count ranking, or `null` if disabled.
  final List<EloItem>? bordaRanking;

  // Parametric batch algorithms
  /// Bradley-Terry MLE ranking, or `null` if disabled.
  final List<EloItem>? bradleyTerryRanking;

  /// TrueSkill conservative-skill ranking, or `null` if disabled.
  final List<EloItem>? trueskillRanking;

  /// Thurstone Case V ranking, or `null` if disabled.
  final List<EloItem>? thurstoneRanking;

  /// SpringRank hierarchy ranking, or `null` if disabled.
  final List<EloItem>? springRankRanking;

  // Graph decomposition algorithms
  /// HodgeRank flow decomposition, or `null` if disabled.
  final HodgeResult? hodge;

  /// SerialRank seriation result, or `null` if disabled.
  final SerialRankResult? serialRank;

  /// Matrix-factorization consensus, or `null` if disabled.
  final MatrixFactorizationResult? matrixFactorization;

  // Ensemble synthesis
  /// Harmonic mean of rank-scores across all non-null rankings.
  /// rank-score = (N − rank_position), so rank 0 → score N, rank N-1 → score 1.
  /// Empty if no algorithms were enabled.
  final List<EloItem> consensusRanking;

  /// Average pairwise Kendall's tau across all non-null rankings. 1.0 = perfect agreement.
  /// Also 1.0 when fewer than 2 algorithms ran.
  final double interAlgorithmKendallTau;

  /// Per-item rank spread across all non-null algorithms.
  final List<AlgorithmDivergence> divergences;

  /// Constructs a comparison. [EloEngine.compareAlgorithms] is the usual
  /// source — consumers rarely build these by hand.
  const RankingComparison({
    this.eloRanking,
    this.glicko2Ranking,
    this.pageRankRanking,
    this.markovRanking,
    this.copelandRanking,
    this.schulzeRanking,
    this.rankedPairsRanking,
    this.bordaRanking,
    this.bradleyTerryRanking,
    this.trueskillRanking,
    this.thurstoneRanking,
    this.springRankRanking,
    this.hodge,
    this.serialRank,
    this.matrixFactorization,
    required this.consensusRanking,
    required this.interAlgorithmKendallTau,
    required this.divergences,
  });
}
