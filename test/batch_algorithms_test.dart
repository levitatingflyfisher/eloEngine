import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';
// Access internal file for batch functions (not in public barrel)
import 'package:elo_engine/src/batch_algorithms.dart';

void main() {
  DateTime ts() => DateTime.now();

  // Helper: build PairwiseMatrix from EloMatch list
  PairwiseMatrix matrix(List<String> ids, List<EloMatch> history) =>
      PairwiseMatrix.fromHistory(ids, history);

  // Linear dominance dataset: a > b > c (a beats b 3×, a beats c 2×, b beats c 1×)
  List<EloMatch> linearHistory() => [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
      ];

  group('bordaRanking', () {
    test('linear dominance → a > b > c', () {
      final m = matrix(['a', 'b', 'c'], linearHistory());
      expect(bordaRanking(m), equals(['a', 'b', 'c']));
    });

    test('single item returns that item', () {
      final m = matrix(['solo'], <EloMatch>[]);
      expect(bordaRanking(m), equals(['solo']));
    });
  });

  group('copelandRanking', () {
    test('linear dominance → a > b > c', () {
      final m = matrix(['a', 'b', 'c'], linearHistory());
      expect(copelandRanking(m), equals(['a', 'b', 'c']));
    });

    test('Condorcet winner identified correctly', () {
      // a beats everyone, b and c are equal (never faced each other)
      final history = [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
      ];
      final m = matrix(['a', 'b', 'c'], history);
      expect(copelandRanking(m).first, 'a');
    });
  });

  group('pageRankRanking', () {
    test('linear dominance → a ranked first', () {
      final m = matrix(['a', 'b', 'c'], linearHistory());
      final ranking = pageRankRanking(m);
      expect(ranking.first, 'a');
    });

    test('isolated item (no wins or losses) still appears in output', () {
      final history = [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
      ];
      final m = matrix(['a', 'b', 'c'], history);
      expect(pageRankRanking(m).length, 3);
    });
  });

  group('markovRanking', () {
    test('linear dominance → a ranked first', () {
      final m = matrix(['a', 'b', 'c'], linearHistory());
      expect(markovRanking(m).first, 'a');
    });

    test('output contains all items', () {
      final m = matrix(['a', 'b', 'c'], linearHistory());
      expect(markovRanking(m).length, 3);
    });
  });

  group('schulzeRanking', () {
    test('linear dominance → a > b > c', () {
      final m = matrix(['a', 'b', 'c'], linearHistory());
      expect(schulzeRanking(m), equals(['a', 'b', 'c']));
    });

    test('Condorcet winner a is ranked first', () {
      // a beats b (5), a beats c (4), b beats c (3) — clear linear order
      final history = [
        ...List.generate(5, (_) =>
            EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts())),
        ...List.generate(4, (_) =>
            EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts())),
        ...List.generate(3, (_) =>
            EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts())),
      ];
      final m = matrix(['a', 'b', 'c'], history);
      expect(schulzeRanking(m).first, 'a');
    });
  });

  group('rankedPairsRanking', () {
    test('linear dominance → a > b > c', () {
      final m = matrix(['a', 'b', 'c'], linearHistory());
      expect(rankedPairsRanking(m), equals(['a', 'b', 'c']));
    });

    test('cycle resolved by locking strongest victories first', () {
      // a beats b (5), b beats c (5), c beats a (3) → locks a>b and b>c; c>a skipped
      final history = [
        ...List.generate(5, (_) =>
            EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts())),
        ...List.generate(5, (_) =>
            EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts())),
        ...List.generate(3, (_) =>
            EloMatch(idA: 'c', idB: 'a', outcome: MatchOutcome.aWins, timestamp: ts())),
      ];
      final m = matrix(['a', 'b', 'c'], history);
      expect(rankedPairsRanking(m), equals(['a', 'b', 'c']));
    });
  });
}
