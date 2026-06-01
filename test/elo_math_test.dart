import 'package:test/test.dart';
import 'package:elo_engine/src/elo_math.dart';

void main() {
  group('expectedScore', () {
    test('equal ratings = 0.5', () {
      expect(expectedScore(1200, 1200), closeTo(0.5, 0.0001));
    });

    test('higher rated wins more often', () {
      final e = expectedScore(1400, 1200);
      expect(e, greaterThan(0.5));
      expect(e, closeTo(0.7597, 0.001));
    });

    test('symmetric: E_A + E_B = 1.0', () {
      final eA = expectedScore(1300, 1100);
      final eB = expectedScore(1100, 1300);
      expect(eA + eB, closeTo(1.0, 0.0001));
    });
  });

  group('kFactor', () {
    const stages = {0: 64, 10: 32, 30: 16};

    test('< 10 matches → K=64', () {
      expect(kFactor(0, stages), 64);
      expect(kFactor(9, stages), 64);
    });

    test('10–29 matches → K=32', () {
      expect(kFactor(10, stages), 32);
      expect(kFactor(29, stages), 32);
    });

    test('>= 30 matches → K=16', () {
      expect(kFactor(30, stages), 16);
      expect(kFactor(100, stages), 16);
    });
  });

  group('applyElo', () {
    test('winner gains, loser loses, sum conserved when K factors equal', () {
      final result = applyElo(
        ratingA: 1200, ratingB: 1200,
        matchCountA: 0, matchCountB: 0,
        scoreA: 1.0,
        kFactorStages: const {0: 64, 10: 32, 30: 16},
      );
      expect(result.deltaA, greaterThan(0));
      expect(result.ratingA + result.ratingB, closeTo(2400, 0.001));
    });

    test('equal ratings, A wins: delta ≈ 32 (K=64, score=1, expected=0.5)', () {
      final result = applyElo(
        ratingA: 1200, ratingB: 1200,
        matchCountA: 0, matchCountB: 0,
        scoreA: 1.0,
        kFactorStages: const {0: 64, 10: 32, 30: 16},
      );
      expect(result.deltaA, closeTo(32.0, 0.001));
    });

    test('tie: both ratings unchanged from equal start', () {
      final result = applyElo(
        ratingA: 1200, ratingB: 1200,
        matchCountA: 0, matchCountB: 0,
        scoreA: 0.5,
        kFactorStages: const {0: 64, 10: 32, 30: 16},
      );
      expect(result.deltaA, closeTo(0.0, 0.001));
      expect(result.ratingA, closeTo(1200.0, 0.001));
      expect(result.ratingB, closeTo(1200.0, 0.001));
    });

    test('uses correct K factor per item matchCount', () {
      final result = applyElo(
        ratingA: 1200, ratingB: 1200,
        matchCountA: 0, matchCountB: 30,
        scoreA: 1.0,
        kFactorStages: const {0: 64, 10: 32, 30: 16},
      );
      expect(result.deltaA, closeTo(32.0, 0.001));   // 64 * 0.5
      expect(result.ratingB, closeTo(1192.0, 0.001)); // 1200 + 16 * (0 - 0.5)
    });
  });

  group('kendallTau', () {
    test('identical orderings → 1.0', () {
      expect(kendallTau(['a', 'b', 'c'], ['a', 'b', 'c']), closeTo(1.0, 0.001));
    });

    test('reversed ordering → -1.0', () {
      expect(kendallTau(['a', 'b', 'c'], ['c', 'b', 'a']), closeTo(-1.0, 0.001));
    });

    test('one swap → 0.333', () {
      expect(kendallTau(['a', 'b', 'c'], ['a', 'c', 'b']), closeTo(1 / 3, 0.001));
    });

    test('single item → 1.0', () {
      expect(kendallTau(['a'], ['a']), 1.0);
    });
  });
}
