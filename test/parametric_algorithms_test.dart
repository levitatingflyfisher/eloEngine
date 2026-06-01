import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';
// Internal file — not in the public barrel, but importable from tests.
import 'package:elo_engine/src/parametric_algorithms.dart';

void main() {
  DateTime ts() => DateTime.now();

  PairwiseMatrix buildMatrix(List<String> ids, List<EloMatch> history) =>
      PairwiseMatrix.fromHistory(ids, history);

  // Linear dominance: a beats b 3×, b beats c 3×, a beats c 2×
  PairwiseMatrix linearMatrix() => buildMatrix(['a', 'b', 'c'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);

  group('bradleyTerryRanking', () {
    test('linear dominance → a > b > c', () {
      expect(bradleyTerryRanking(linearMatrix()), equals(['a', 'b', 'c']));
    });

    test('single item → [that item]', () {
      final m = buildMatrix(['x'], []);
      expect(bradleyTerryRanking(m), equals(['x']));
    });

    test('no matches → returns all ids without crash', () {
      final m = buildMatrix(['a', 'b', 'c'], []);
      expect(bradleyTerryRanking(m), hasLength(3));
    });

    test('symmetric cycle (a>b, b>c, c>a 3× each) → all items in output', () {
      final m = buildMatrix(['a', 'b', 'c'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'a', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'a', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'a', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      final result = bradleyTerryRanking(m);
      expect(result, containsAll(['a', 'b', 'c']));
      expect(result, hasLength(3));
    });

    test('dominant winner ranked first across 4 items', () {
      final m = buildMatrix(['a', 'b', 'c', 'd'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      expect(bradleyTerryRanking(m).first, 'a');
    });
  });

  group('thurstoneRanking', () {
    test('linear dominance → a > b > c', () {
      expect(thurstoneRanking(linearMatrix()), equals(['a', 'b', 'c']));
    });

    test('single item → [that item]', () {
      final m = buildMatrix(['x'], []);
      expect(thurstoneRanking(m), equals(['x']));
    });

    test('item with no comparisons still appears in output', () {
      final m = buildMatrix(['a', 'b', 'c', 'd'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      final result = thurstoneRanking(m);
      expect(result, containsAll(['a', 'b', 'c', 'd']));
      expect(result, hasLength(4));
    });

    test('dominant winner ranked first across 4 items', () {
      final m = buildMatrix(['a', 'b', 'c', 'd'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      expect(thurstoneRanking(m).first, 'a');
    });
  });

  group('springRankRanking', () {
    test('linear dominance → a > b > c', () {
      expect(springRankRanking(linearMatrix()), equals(['a', 'b', 'c']));
    });

    test('two-item case: winner ranked first', () {
      final m = buildMatrix(['a', 'b'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      expect(springRankRanking(m).first, 'a');
    });

    test('item with no comparisons still appears in output', () {
      final m = buildMatrix(['a', 'b', 'c', 'd'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      final result = springRankRanking(m);
      expect(result, containsAll(['a', 'b', 'c', 'd']));
      expect(result, hasLength(4));
    });

    test('dominant winner ranked first across 4 items', () {
      final m = buildMatrix(['a', 'b', 'c', 'd'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      expect(springRankRanking(m).first, 'a');
    });
  });

  group('hodgeRanking', () {
    test('linear dominance → a > b > c', () {
      final result = hodgeRanking(linearMatrix());
      expect(result.ranking, equals(['a', 'b', 'c']));
    });

    test('empty → [], cyclicMagnitude=0, harmonicMagnitude=0', () {
      final result = hodgeRanking(buildMatrix([], []));
      expect(result.ranking, isEmpty);
      expect(result.cyclicMagnitude, closeTo(0.0, 1e-9));
      expect(result.harmonicMagnitude, closeTo(0.0, 1e-9));
    });

    test('single item → [that item], cyclicMagnitude=0, harmonicMagnitude=0', () {
      final result = hodgeRanking(buildMatrix(['x'], []));
      expect(result.ranking, equals(['x']));
      expect(result.cyclicMagnitude, closeTo(0.0, 1e-9));
      expect(result.harmonicMagnitude, closeTo(0.0, 1e-9));
    });

    test('cyclicMagnitude ∈ [0, 1]', () {
      final result = hodgeRanking(linearMatrix());
      expect(result.cyclicMagnitude, greaterThanOrEqualTo(0.0));
      expect(result.cyclicMagnitude, lessThanOrEqualTo(1.0));
    });

    test('harmonicMagnitude = 0 when all pairs compared, > 0 when some uncompared', () {
      // linearMatrix has all 3 pairs compared.
      expect(hodgeRanking(linearMatrix()).harmonicMagnitude, closeTo(0.0, 1e-9));

      // Path graph: a→b, b→c but no a→c (1 of 3 pairs missing).
      final path = buildMatrix(['a', 'b', 'c'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      expect(hodgeRanking(path).harmonicMagnitude, greaterThan(0.0));
    });

    test('symmetric 3-cycle → cyclicMagnitude ≈ 1.0 (pure cyclic flow)', () {
      final m = buildMatrix(['a', 'b', 'c'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'a', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      expect(hodgeRanking(m).cyclicMagnitude, closeTo(1.0, 0.01));
    });
  });

  group('serialRanking', () {
    test('linear dominance → a > b > c', () {
      expect(serialRanking(linearMatrix()).ranking, equals(['a', 'b', 'c']));
    });

    test('empty → [], rankability = 1.0', () {
      final result = serialRanking(buildMatrix([], []));
      expect(result.ranking, isEmpty);
      expect(result.rankability, closeTo(1.0, 1e-9));
    });

    test('single item → [that item], rankability = 1.0', () {
      final result = serialRanking(buildMatrix(['x'], []));
      expect(result.ranking, equals(['x']));
      expect(result.rankability, closeTo(1.0, 1e-9));
    });

    test('perfect linear dominance → rankability = 1.0', () {
      expect(serialRanking(linearMatrix()).rankability, closeTo(1.0, 1e-9));
    });

    test('rankability ∈ [0, 1]', () {
      final r = serialRanking(linearMatrix()).rankability;
      expect(r, greaterThanOrEqualTo(0.0));
      expect(r, lessThanOrEqualTo(1.0));
    });

    test('dominant winner ranked first across 4 items', () {
      final m = buildMatrix(['a', 'b', 'c', 'd'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      expect(serialRanking(m).ranking.first, 'a');
    });

    test('symmetric 3-cycle → rankability < 1.0', () {
      final m = buildMatrix(['a', 'b', 'c'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'a', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      expect(serialRanking(m).rankability, lessThan(1.0));
    });
  });

  group('matrixFactorizationRanking', () {
    test('linear dominance → a > b > c', () {
      expect(
          matrixFactorizationRanking(linearMatrix()).ranking, equals(['a', 'b', 'c']));
    });

    test('single item → bestRank=1, explainedVariance=1.0', () {
      final result = matrixFactorizationRanking(buildMatrix(['x'], []));
      expect(result.ranking, equals(['x']));
      expect(result.bestRank, 1);
      expect(result.explainedVariance, closeTo(1.0, 1e-9));
    });

    test('no comparisons (traceM≈0) → original order, bestRank=1, explainedVariance=0', () {
      final result = matrixFactorizationRanking(buildMatrix(['a', 'b', 'c'], []));
      expect(result.ranking, equals(['a', 'b', 'c']));
      expect(result.bestRank, 1);
      expect(result.explainedVariance, closeTo(0.0, 1e-9));
    });

    test('bestRank ∈ [1, 3]', () {
      final r = matrixFactorizationRanking(linearMatrix()).bestRank;
      expect(r, greaterThanOrEqualTo(1));
      expect(r, lessThanOrEqualTo(3));
    });

    test('explainedVariance ∈ [0, 1]', () {
      final r = matrixFactorizationRanking(linearMatrix()).explainedVariance;
      expect(r, greaterThanOrEqualTo(0.0));
      expect(r, lessThanOrEqualTo(1.0));
    });

    test('dominant winner ranked first across 4 items', () {
      final m = buildMatrix(['a', 'b', 'c', 'd'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'c', idB: 'd', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      expect(matrixFactorizationRanking(m).ranking.first, 'a');
    });

    test('2-item case: bestRank = 1 (maxK=1, not exceeding found eigenvectors)', () {
      final m = buildMatrix(['a', 'b'], [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
      ]);
      final result = matrixFactorizationRanking(m);
      expect(result.bestRank, 1);
      expect(result.ranking.first, 'a');
    });
  });
}
