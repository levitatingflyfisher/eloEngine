import 'models.dart';
import 'session.dart';

/// Strategy for combining per-participant rankings into a single ranking.
///
/// All strategies are score-based: each participant's items are sorted by
/// rating, and an item at 0-indexed rank `r` in a session of `N` items
/// receives a score of `N − r` (so the best item scores `N`, the worst
/// scores `1`). The strategy aggregates per-item scores across participants.
///
/// - [harmonicMean] (default): penalizes disagreement. An item ranked #1 by
///   one partner and #45 by the other scores worse than an item that is
///   #25 for both. Surfaces genuine consensus, not enthusiastic outliers.
///   See PRD §11.
/// - [arithmeticMean]: simple average. A single passionate vote can drag
///   a middling item upward.
/// - [minimum]: as good as the worst rating it received. Strictest filter:
///   if any participant ranked an item poorly, the merged score is poor.
enum MergeStrategy {
  /// Penalizes disagreement. An item ranked #1 by one partner and #45 by
  /// another scores worse than an item that's #25 for both. Default.
  harmonicMean,

  /// Simple average. One passionate vote can drag a middling item upward.
  arithmeticMean,

  /// As good as the worst rating it received. Strictest filter.
  minimum,
}

/// One row in the merged result list returned by [EloMerge.combine].
class MergedResult {
  /// The item, drawn from the first session in the input list. Other
  /// sessions' [EloItem] instances are matched by [EloItem.id] only.
  final EloItem item;

  /// 0-indexed rank in each participant's session, in the order sessions
  /// were passed to [EloMerge.combine].
  final List<int> ranksByParticipant;

  /// Combined score from the chosen [MergeStrategy]. Higher = better.
  /// Range depends on the strategy and N; for all built-in strategies the
  /// range is `[1, N]`.
  final double combinedScore;

  /// Inter-participant agreement, in `[0.0, 1.0]`.
  ///
  /// `1.0` = all participants ranked this item identically. `0.0` = at
  /// least one participant ranked it #1 and another ranked it last.
  /// Computed as `1 − (max_rank − min_rank) / (N − 1)`. Trivially `1.0`
  /// for `N ≤ 1`.
  final double agreement;

  /// Constructs a merged result entry.
  const MergedResult({
    required this.item,
    required this.ranksByParticipant,
    required this.combinedScore,
    required this.agreement,
  });
}

/// Combine independent ranking sessions over a shared item set.
///
/// Use case: a couple picking a baby name shares one phone. Each partner
/// builds an [EloEngine] independently, calls [EloEngine.snapshot], and the
/// snapshots are passed here. The result surfaces names both people like.
///
/// All input sessions must contain the same set of item IDs. Item ratings
/// can (and should) differ — they reflect each participant's independent
/// comparisons.
class EloMerge {
  EloMerge._();

  /// Combine N sessions into a single merged ranking.
  ///
  /// Throws [ArgumentError] if [sessions] is empty or if sessions contain
  /// different item ID sets.
  static List<MergedResult> combine(
    List<EloSession> sessions, {
    MergeStrategy strategy = MergeStrategy.harmonicMean,
  }) {
    if (sessions.isEmpty) {
      throw ArgumentError('At least one session required');
    }

    // Validate: all sessions must have the same item ID set.
    final firstIds = sessions[0].items.map((i) => i.id).toSet();
    for (var i = 1; i < sessions.length; i++) {
      final ids = sessions[i].items.map((i) => i.id).toSet();
      if (ids.length != firstIds.length || !ids.containsAll(firstIds)) {
        throw ArgumentError(
            'All sessions must contain the same item ID set; mismatch at session $i');
      }
    }

    if (firstIds.isEmpty) return const [];

    final n = firstIds.length;

    // Compute each participant's 0-indexed rank for every item.
    final perParticipantRanks = <Map<String, int>>[];
    for (final session in sessions) {
      final sorted = List<EloItem>.from(session.items)
        ..sort((a, b) => b.rating.compareTo(a.rating));
      final rankMap = <String, int>{};
      for (var pos = 0; pos < sorted.length; pos++) {
        rankMap[sorted[pos].id] = pos;
      }
      perParticipantRanks.add(rankMap);
    }

    // Build merged result for each item, using the first session's EloItem
    // instances as the canonical references.
    final results = <MergedResult>[];
    for (final item in sessions[0].items) {
      final itemRanks = <int>[
        for (final ranks in perParticipantRanks) ranks[item.id]!,
      ];

      // score = N − rank, so rank 0 → score N, rank N−1 → score 1.
      // Range [1, N], strictly positive — safe for harmonic mean.
      final scores = itemRanks.map((r) => (n - r).toDouble()).toList();

      final combined = switch (strategy) {
        MergeStrategy.harmonicMean => _harmonicMean(scores),
        MergeStrategy.arithmeticMean => _arithmeticMean(scores),
        MergeStrategy.minimum => scores.reduce((a, b) => a < b ? a : b),
      };

      final maxRank = itemRanks.reduce((a, b) => a > b ? a : b);
      final minRank = itemRanks.reduce((a, b) => a < b ? a : b);
      final agreement =
          n <= 1 ? 1.0 : 1.0 - (maxRank - minRank) / (n - 1);

      results.add(MergedResult(
        item: item,
        ranksByParticipant: itemRanks,
        combinedScore: combined,
        agreement: agreement,
      ));
    }

    results.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));
    return results;
  }

  static double _harmonicMean(List<double> values) {
    var sumReciprocal = 0.0;
    for (final v in values) {
      sumReciprocal += 1.0 / v;
    }
    return values.length / sumReciprocal;
  }

  static double _arithmeticMean(List<double> values) {
    var sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    return sum / values.length;
  }
}
