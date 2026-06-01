import 'models.dart';

/// Compact pairwise comparison matrix derived from match history.
/// Shared input for all batch ranking algorithms.
class PairwiseMatrix {
  /// Item IDs indexed into the matrix. `wins[i][j]` uses these positions.
  final List<String> ids;

  /// wins[i][j] = number of times item i beat item j.
  final List<List<int>> wins;

  /// ties[i][j] = number of ties between i and j (symmetric: ties[i][j] == ties[j][i]).
  ///
  /// **Warning:** Each tie is recorded in both [i][j] and [j][i]. When aggregating
  /// across all pairs, read only one triangle to avoid double-counting.
  /// Use [matchesBetween] for safe pair-total computation.
  final List<List<int>> ties;

  PairwiseMatrix._({
    required this.ids,
    required this.wins,
    required this.ties,
  });

  /// Builds a pairwise matrix from match history for the given [ids].
  /// Skips (`MatchOutcome.skip`) and matches involving unknown IDs are
  /// ignored. Each tie increments both `[i][j]` and `[j][i]`.
  factory PairwiseMatrix.fromHistory(
    List<String> ids,
    List<EloMatch> history,
  ) {
    final n = ids.length;
    final index = {for (var i = 0; i < n; i++) ids[i]: i};
    final wins = List.generate(n, (_) => List.filled(n, 0));
    final ties = List.generate(n, (_) => List.filled(n, 0));

    for (final m in history) {
      if (m.outcome == MatchOutcome.skip) continue;
      final i = index[m.idA];
      final j = index[m.idB];
      if (i == null || j == null) continue;
      switch (m.outcome) {
        case MatchOutcome.aWins:
          wins[i][j]++;
        case MatchOutcome.bWins:
          wins[j][i]++;
        case MatchOutcome.tie:
          ties[i][j]++;
          ties[j][i]++;
        default:
          // skip is unreachable; guarded by if-continue above
          break;
      }
    }

    return PairwiseMatrix._(ids: ids, wins: wins, ties: ties);
  }

  /// Number of items in the matrix.
  int get n => ids.length;

  /// Total non-skip comparisons between items at indices [i] and [j].
  int matchesBetween(int i, int j) => wins[i][j] + wins[j][i] + ties[i][j];

  /// W[i][j] = wins[i][j] / matchesBetween(i, j).
  /// Returns 0.5 for unseen off-diagonal pairs, and 0.0 on the diagonal.
  List<List<double>> get winRateMatrix {
    return List.generate(n, (i) => List.generate(n, (j) {
      if (i == j) return 0.0;
      final total = matchesBetween(i, j);
      return total == 0 ? 0.5 : wins[i][j] / total;
    }));
  }
}
