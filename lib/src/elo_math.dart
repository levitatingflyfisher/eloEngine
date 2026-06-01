import 'dart:math';

/// Expected score for item A given ratings ratingA and ratingB.
/// Returns a value in (0, 1). 0.5 when ratings are equal.
double expectedScore(double ratingA, double ratingB) =>
    1.0 / (1.0 + pow(10.0, (ratingB - ratingA) / 400.0));

/// K-factor for an item with [matchCount] completed comparisons.
/// [stages] maps minimum match count → K value. E.g. {0: 64, 10: 32, 30: 16}.
int kFactor(int matchCount, Map<int, int> stages) {
  assert(stages.isNotEmpty, 'kFactorStages must not be empty');
  final thresholds = stages.keys.toList()..sort();
  var result = stages[thresholds.first]!;
  for (final t in thresholds) {
    if (matchCount >= t) result = stages[t]!;
  }
  return result;
}

/// Result of applying ELO to one comparison.
class EloUpdateResult {
  /// New rating for item A.
  final double ratingA;

  /// New rating for item B.
  final double ratingB;

  /// Rating change applied to A; B's delta is the negation.
  final double deltaA;

  /// Constructs an update result.
  const EloUpdateResult({
    required this.ratingA,
    required this.ratingB,
    required this.deltaA,
  });
}

/// Apply ELO update for one comparison. [scoreA] is 1.0 (win), 0.5 (tie), 0.0 (loss).
/// Uses per-item K-factors from [kFactorStages].
EloUpdateResult applyElo({
  required double ratingA,
  required double ratingB,
  required int matchCountA,
  required int matchCountB,
  required double scoreA,
  required Map<int, int> kFactorStages,
}) {
  assert(scoreA >= 0.0 && scoreA <= 1.0, 'scoreA must be in [0.0, 1.0]');
  final eA = expectedScore(ratingA, ratingB);
  final kA = kFactor(matchCountA, kFactorStages);
  final kB = kFactor(matchCountB, kFactorStages);
  final deltaA = kA * (scoreA - eA);
  final deltaB = kB * ((1 - scoreA) - (1 - eA));
  return EloUpdateResult(
    ratingA: ratingA + deltaA,
    ratingB: ratingB + deltaB,
    deltaA: deltaA,
  );
}

/// Kendall's tau-a between two complete rank orderings with no ties.
/// Both lists must contain the same elements in a different order.
/// Returns a value in [-1, 1]. 1.0 = perfect agreement, -1.0 = perfect reversal.
/// Note: for ELO rank orderings (no tied ranks), tau-a and tau-b are identical.
double kendallTau(List<String> rankingA, List<String> rankingB) {
  final n = rankingA.length;
  if (n <= 1) return 1.0;
  final posB = <String, int>{};
  for (var i = 0; i < rankingB.length; i++) {
    posB[rankingB[i]] = i;
  }
  var concordant = 0;
  var discordant = 0;
  for (var i = 0; i < n - 1; i++) {
    for (var j = i + 1; j < n; j++) {
      final pi = posB[rankingA[i]]!;
      final pj = posB[rankingA[j]]!;
      if (pi < pj) {
        concordant++;
      } else {
        discordant++;
      }
    }
  }
  final total = n * (n - 1) ~/ 2;
  return (concordant - discordant) / total;
}
