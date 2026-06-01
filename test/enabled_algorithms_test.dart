import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';

/// Build a small engine with enough history that every batch algorithm
/// has data to work with. Deterministic outcomes: a > b > c > d.
EloEngine _buildEngine({EloConfig? config}) {
  final engine = EloEngine(
    items: [
      EloItem(id: 'a'),
      EloItem(id: 'b'),
      EloItem(id: 'c'),
      EloItem(id: 'd'),
    ],
    config: config,
  );
  engine.record('a', 'b', MatchOutcome.aWins);
  engine.record('a', 'c', MatchOutcome.aWins);
  engine.record('a', 'd', MatchOutcome.aWins);
  engine.record('b', 'c', MatchOutcome.aWins);
  engine.record('b', 'd', MatchOutcome.aWins);
  engine.record('c', 'd', MatchOutcome.aWins);
  return engine;
}

void main() {
  group('EloConfig.enabledAlgorithms', () {
    test('null (default) runs all 15 algorithms', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.eloRanking, isNotNull);
      expect(result.glicko2Ranking, isNotNull);
      expect(result.trueskillRanking, isNotNull);
      expect(result.bordaRanking, isNotNull);
      expect(result.copelandRanking, isNotNull);
      expect(result.pageRankRanking, isNotNull);
      expect(result.markovRanking, isNotNull);
      expect(result.schulzeRanking, isNotNull);
      expect(result.rankedPairsRanking, isNotNull);
      expect(result.bradleyTerryRanking, isNotNull);
      expect(result.thurstoneRanking, isNotNull);
      expect(result.springRankRanking, isNotNull);
      expect(result.hodge, isNotNull);
      expect(result.serialRank, isNotNull);
      expect(result.matrixFactorization, isNotNull);
      expect(result.divergences.first.rankByAlgorithm.length, equals(15));
    });

    test('empty set throws ArgumentError at engine construction', () {
      expect(
        () => EloEngine(
          items: [EloItem(id: 'a')],
          config: const EloConfig(enabledAlgorithms: {}),
        ),
        throwsArgumentError,
      );
    });

    test('subset: only listed algorithms are non-null', () {
      final result = _buildEngine(
        config: const EloConfig(enabledAlgorithms: {
          AlgorithmId.elo,
          AlgorithmId.borda,
        }),
      ).compareAlgorithms();

      // Enabled
      expect(result.eloRanking, isNotNull);
      expect(result.bordaRanking, isNotNull);

      // Every other algorithm is null
      expect(result.glicko2Ranking, isNull);
      expect(result.trueskillRanking, isNull);
      expect(result.copelandRanking, isNull);
      expect(result.pageRankRanking, isNull);
      expect(result.markovRanking, isNull);
      expect(result.schulzeRanking, isNull);
      expect(result.rankedPairsRanking, isNull);
      expect(result.bradleyTerryRanking, isNull);
      expect(result.thurstoneRanking, isNull);
      expect(result.springRankRanking, isNull);
      expect(result.hodge, isNull);
      expect(result.serialRank, isNull);
      expect(result.matrixFactorization, isNull);
    });

    test('divergences aggregate only over enabled algorithms', () {
      final result = _buildEngine(
        config: const EloConfig(enabledAlgorithms: {
          AlgorithmId.elo,
          AlgorithmId.borda,
          AlgorithmId.copeland,
        }),
      ).compareAlgorithms();
      for (final d in result.divergences) {
        expect(d.rankByAlgorithm.keys, equals({
          AlgorithmId.elo,
          AlgorithmId.borda,
          AlgorithmId.copeland,
        }));
      }
    });

    test('consensusRanking honours enabled subset', () {
      final result = _buildEngine(
        config: const EloConfig(enabledAlgorithms: {AlgorithmId.elo}),
      ).compareAlgorithms();
      // With only ELO enabled, consensus must equal ELO order.
      expect(result.consensusRanking.map((i) => i.id),
          equals(result.eloRanking!.map((i) => i.id)));
    });

    test('single algorithm: interAlgorithmKendallTau is 1.0', () {
      final result = _buildEngine(
        config: const EloConfig(enabledAlgorithms: {AlgorithmId.elo}),
      ).compareAlgorithms();
      expect(result.interAlgorithmKendallTau, equals(1.0));
    });

    test('disabling glicko2 skips per-match state updates', () {
      // We can't directly observe the skipped work, but if compareAlgorithms
      // is then called and glicko2 is off, the result is null — and a later
      // re-enable via a fresh engine should produce a non-null result.
      final off = _buildEngine(
        config: const EloConfig(enabledAlgorithms: {AlgorithmId.elo}),
      ).compareAlgorithms();
      expect(off.glicko2Ranking, isNull);

      final on = _buildEngine().compareAlgorithms();
      expect(on.glicko2Ranking, isNotNull);
    });

    test('disabling trueskill skips per-match state updates', () {
      final off = _buildEngine(
        config: const EloConfig(enabledAlgorithms: {AlgorithmId.elo}),
      ).compareAlgorithms();
      expect(off.trueskillRanking, isNull);
    });

    test('JSON round-trip preserves enabledAlgorithms', () {
      const cfg = EloConfig(enabledAlgorithms: {
        AlgorithmId.elo,
        AlgorithmId.borda,
        AlgorithmId.schulze,
      });
      final restored = EloConfig.fromJson(cfg.toJson());
      expect(restored.enabledAlgorithms, equals(cfg.enabledAlgorithms));
    });

    test('JSON round-trip with null enabledAlgorithms', () {
      const cfg = EloConfig();
      final restored = EloConfig.fromJson(cfg.toJson());
      expect(restored.enabledAlgorithms, isNull);
    });

    test('fromJson after toJson preserves subset through full engine cycle',
        () {
      final engine = _buildEngine(
        config: const EloConfig(enabledAlgorithms: {
          AlgorithmId.elo,
          AlgorithmId.borda,
        }),
      );
      final json = engine.toJson();
      final restored = EloEngine.fromJson(json);
      final result = restored.compareAlgorithms();
      expect(result.bordaRanking, isNotNull);
      expect(result.glicko2Ranking, isNull);
      expect(result.schulzeRanking, isNull);
    });

    test('disabling all batch algorithms skips PairwiseMatrix construction',
        () {
      // This is a behavioural test: if compareAlgorithms threw because it
      // tried to build a matrix it didn't need, the test would fail. With
      // only online algos enabled, we should get a valid result.
      final result = _buildEngine(
        config: const EloConfig(enabledAlgorithms: {
          AlgorithmId.elo,
          AlgorithmId.glicko2,
          AlgorithmId.trueskill,
        }),
      ).compareAlgorithms();
      expect(result.eloRanking, isNotNull);
      expect(result.glicko2Ranking, isNotNull);
      expect(result.trueskillRanking, isNotNull);
      expect(result.bordaRanking, isNull);
    });

    test('single enabled: every other algorithm field is null', () {
      for (final id in AlgorithmId.values) {
        final result = _buildEngine(
          config: EloConfig(enabledAlgorithms: {id}),
        ).compareAlgorithms();
        // Exactly one non-null entry in the divergence map for any item.
        expect(
          result.divergences.first.rankByAlgorithm.keys.single,
          equals(id),
          reason: 'only $id should report a rank',
        );
      }
    });
  });
}
