import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';

void main() {
  DateTime ts() => DateTime.now();

  group('PairwiseMatrix', () {
    test('builds correct win counts from history', () {
      final history = [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'b', idB: 'c', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'c', outcome: MatchOutcome.bWins, timestamp: ts()),
      ];
      final m = PairwiseMatrix.fromHistory(['a', 'b', 'c'], history);
      expect(m.wins[0][1], 1); // a beat b
      expect(m.wins[1][2], 1); // b beat c
      expect(m.wins[2][0], 1); // c beat a
      expect(m.wins[1][0], 0); // b never beat a
    });

    test('records ties symmetrically', () {
      final history = [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.tie, timestamp: ts()),
      ];
      final m = PairwiseMatrix.fromHistory(['a', 'b'], history);
      expect(m.ties[0][1], 1);
      expect(m.ties[1][0], 1); // symmetric
      expect(m.wins[0][1], 0);
    });

    test('skips are excluded from win and tie counts', () {
      final history = [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.skip, timestamp: ts()),
      ];
      final m = PairwiseMatrix.fromHistory(['a', 'b'], history);
      expect(m.wins[0][1], 0);
      expect(m.wins[1][0], 0);
      expect(m.ties[0][1], 0);
    });

    test('matchesBetween counts non-skip comparisons only', () {
      final history = [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.tie, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.skip, timestamp: ts()),
      ];
      final m = PairwiseMatrix.fromHistory(['a', 'b'], history);
      expect(m.matchesBetween(0, 1), 2); // 1 win + 1 tie; skip excluded
    });

    test('winRateMatrix: correct rate, 0.5 for unseen, 0.0 on diagonal', () {
      // a beat b twice, tied once: rate = 2/3
      final history = [
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.aWins, timestamp: ts()),
        EloMatch(idA: 'a', idB: 'b', outcome: MatchOutcome.tie, timestamp: ts()),
      ];
      final m = PairwiseMatrix.fromHistory(['a', 'b', 'c'], history);
      final w = m.winRateMatrix;
      expect(w[0][1], closeTo(2 / 3, 0.001)); // a beat b 2 of 3
      expect(w[1][2], closeTo(0.5, 0.001));    // b vs c: unseen → 0.5
      expect(w[0][0], 0.0);                    // diagonal
    });
  });
}
