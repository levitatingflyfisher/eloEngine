import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';

void main() {
  group('EloItem', () {
    test('starts at configured rating', () {
      final item = EloItem(id: 'a');
      expect(item.rating, 1200.0);
      expect(item.matchCount, 0);
      expect(item.lastSeen, isNull);
    });

    test('serializes and deserializes', () {
      final item = EloItem(id: 'x', rating: 1350.5, matchCount: 7,
          lastSeen: DateTime.fromMillisecondsSinceEpoch(1711000000 * 1000));
      final roundTripped = EloItem.fromJson(item.toJson());
      expect(roundTripped.id, 'x');
      expect(roundTripped.rating, closeTo(1350.5, 0.001));
      expect(roundTripped.matchCount, 7);
      expect(roundTripped.lastSeen!.millisecondsSinceEpoch,
          item.lastSeen!.millisecondsSinceEpoch);
    });
  });

  group('EloConfig', () {
    test('defaults match PRD', () {
      const cfg = EloConfig();
      expect(cfg.startingRating, 1200);
      expect(cfg.kFactorStages[0], 64);
      expect(cfg.kFactorStages[10], 32);
      expect(cfg.kFactorStages[30], 16);
      expect(cfg.convergenceTau, 0.95);
    });
  });

  group('EloMatch', () {
    test('serializes and deserializes all outcomes', () {
      for (final outcome in MatchOutcome.values) {
        final match = EloMatch(
          idA: 'a', idB: 'b',
          outcome: outcome,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1711000000 * 1000),
        );
        final rt = EloMatch.fromJson(match.toJson());
        expect(rt.idA, 'a');
        expect(rt.idB, 'b');
        expect(rt.outcome, outcome);
      }
    });
  });

  group('EloEngine.record', () {
    test('winner gains rating, loser loses', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      final result = engine.record('a', 'b', MatchOutcome.aWins);
      expect(result.deltaA, greaterThan(0));
      expect(result.itemA.rating, greaterThan(1200));
      expect(result.itemB.rating, lessThan(1200));
    });

    test('increments matchCount for both items', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      engine.record('a', 'b', MatchOutcome.aWins);
      expect(engine.rankings[0].matchCount, 1);
      expect(engine.rankings[1].matchCount, 1);
    });

    test('skip does not change ratings or matchCount', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      final result = engine.record('a', 'b', MatchOutcome.skip);
      expect(result.deltaA, 0.0);
      expect(result.itemA.rating, 1200.0);
      expect(result.itemB.rating, 1200.0);
      expect(result.itemA.matchCount, 0);
      expect(result.itemB.matchCount, 0);
    });

    test('throws ArgumentError for unknown id', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      expect(() => engine.record('a', 'z', MatchOutcome.aWins),
          throwsArgumentError);
    });

    test('allowTies=false rejects MatchOutcome.tie', () {
      final engine = EloEngine(
        items: [EloItem(id: 'a'), EloItem(id: 'b')],
        config: const EloConfig(allowTies: false),
      );
      expect(() => engine.record('a', 'b', MatchOutcome.tie),
          throwsArgumentError);
    });

    test('allowTies=false still accepts wins, losses, and skips', () {
      final engine = EloEngine(
        items: [EloItem(id: 'a'), EloItem(id: 'b')],
        config: const EloConfig(allowTies: false),
      );
      expect(() => engine.record('a', 'b', MatchOutcome.aWins), returnsNormally);
      expect(() => engine.record('a', 'b', MatchOutcome.bWins), returnsNormally);
      expect(() => engine.record('a', 'b', MatchOutcome.skip), returnsNormally);
    });

    test('allowTies=true (default) accepts ties', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      expect(() => engine.record('a', 'b', MatchOutcome.tie), returnsNormally);
    });

    test('allowTies=false trusts historical ties in constructor', () {
      final history = [
        EloMatch(
            idA: 'a',
            idB: 'b',
            outcome: MatchOutcome.tie,
            timestamp: DateTime.now()),
      ];
      // Constructing with a history that contains ties must not throw,
      // even when the current policy forbids new ties.
      expect(
        () => EloEngine(
          items: [EloItem(id: 'a'), EloItem(id: 'b')],
          history: history,
          config: const EloConfig(allowTies: false),
        ),
        returnsNormally,
      );
    });

    test('throws ArgumentError for duplicate IDs in constructor', () {
      expect(
          () => EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'a')]),
          throwsArgumentError);
    });
  });

  group('EloEngine.rankings', () {
    test('returns items sorted highest rating first', () {
      final engine = EloEngine(items: [
        EloItem(id: 'a'),
        EloItem(id: 'b'),
        EloItem(id: 'c'),
      ]);
      engine.record('a', 'b', MatchOutcome.aWins);
      engine.record('a', 'c', MatchOutcome.aWins);
      final ranked = engine.rankings;
      expect(ranked.first.id, 'a');
    });
  });

  group('EloEngine.undo', () {
    test('reverts ratings to pre-match state', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      engine.record('a', 'b', MatchOutcome.aWins);
      expect(engine.rankings.first.rating, greaterThan(1200));
      engine.undo();
      expect(engine.rankings.first.rating, 1200.0);
    });

    test('undo after skip reverts correctly (skip is in history)', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      engine.record('a', 'b', MatchOutcome.skip);
      engine.record('a', 'b', MatchOutcome.aWins);
      engine.undo(); // undo the aWins
      expect(engine.rankings.first.matchCount, 0);
      expect(engine.rankings.first.rating, 1200.0);
    });

    test('undo on empty history is a no-op', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      expect(() => engine.undo(), returnsNormally);
    });
  });

  group('EloEngine.nextMatch', () {
    test('returns a pair from the item set', () {
      final engine = EloEngine(items: [
        EloItem(id: 'a'),
        EloItem(id: 'b'),
        EloItem(id: 'c'),
      ]);
      final proposal = engine.nextMatch();
      expect(proposal, isNotNull);
      expect(['a', 'b', 'c'], contains(proposal!.itemA.id));
      expect(['a', 'b', 'c'], contains(proposal.itemB.id));
      expect(proposal.itemA.id, isNot(proposal.itemB.id));
    });

    test('returns null when N < 2', () {
      final engine = EloEngine(items: [EloItem(id: 'a')]);
      expect(engine.nextMatch(), isNull);
    });

    test('prefers equal-rated items (adjacency = 1.0)', () {
      final engine = EloEngine(items: [
        EloItem(id: 'a', matchCount: 5),
        EloItem(id: 'b', matchCount: 5),
        EloItem(id: 'c', matchCount: 0),
        EloItem(id: 'd', matchCount: 0),
      ]);
      final proposal = engine.nextMatch()!;
      expect([proposal.itemA.id, proposal.itemB.id],
          containsAll(['c', 'd']));
    });

    test('recently seen pair is penalised (0.5 priority reduction)', () {
      final engine = EloEngine(items: [
        EloItem(id: 'a'),
        EloItem(id: 'b'),
        EloItem(id: 'c'),
      ]);
      engine.record('a', 'b', MatchOutcome.aWins);
      final proposal = engine.nextMatch()!;
      final ids = {proposal.itemA.id, proposal.itemB.id};
      expect(ids, isNot(equals({'a', 'b'})));
    });

    test('skip suppresses pair from nextMatch within recency window', () {
      final engine = EloEngine(items: [
        EloItem(id: 'a'),
        EloItem(id: 'b'),
        EloItem(id: 'c'),
      ]);
      engine.record('a', 'b', MatchOutcome.skip);
      final proposal = engine.nextMatch()!;
      final ids = {proposal.itemA.id, proposal.itemB.id};
      expect(ids, isNot(equals({'a', 'b'})));
    });

    test('expectedA is close to 0.5 for equal-rated pair', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      final proposal = engine.nextMatch()!;
      expect(proposal.expectedA, closeTo(0.5, 0.01));
    });
  });

  group('EloEngine.isConverged', () {
    test('not converged before minMatchesBeforeConverge', () {
      // convergenceWindow=5 means tau history fills after 5 matches;
      // minMatchesBeforeConverge=20 keeps the gate closed past that point.
      final engine = EloEngine(
        items: List.generate(5, (i) => EloItem(id: 'item$i')),
        config: const EloConfig(
          convergenceTau: 0.5, // very lenient — would pass trivially otherwise
          convergenceWindow: 5,
          minMatchesBeforeConverge: 20,
        ),
      );
      // Record enough matches to fill the tau window, but stay below the gate.
      for (var i = 0; i < 15; i++) {
        engine.record('item${i % 4}', 'item${(i % 4) + 1}', MatchOutcome.aWins);
      }
      // Tau window is full but minMatchesBeforeConverge (20) not yet reached.
      expect(engine.isConverged, isFalse,
          reason: 'minMatchesBeforeConverge gate should still be closed at 15 matches');
    });

    test('converges after stable ranking for 25 consecutive matches', () {
      // Create a session where one item always wins → stable ranking.
      final items = List.generate(5, (i) => EloItem(id: 'item$i'));
      final engine = EloEngine(
        items: items,
        config: const EloConfig(
          convergenceTau: 0.9,
          convergenceWindow: 5,
          minMatchesBeforeConverge: 5,
        ),
      );

      // Force a stable ranking by having item0 always beat everyone else
      // and lower-index items always beat higher-index items.
      // Keep recording until converged or 500 matches.
      var count = 0;
      while (!engine.isConverged && count < 500) {
        for (var i = 0; i < items.length - 1 && !engine.isConverged; i++) {
          engine.record('item$i', 'item${i + 1}', MatchOutcome.aWins);
          count++;
        }
      }
      expect(engine.isConverged, isTrue,
          reason: 'should converge within 500 matches on stable ordering');
    });
  });

  group('EloEngine JSON serialization', () {
    EloEngine _buildEngine() {
      final engine = EloEngine(items: [
        EloItem(id: 'eliot'),
        EloItem(id: 'james'),
        EloItem(id: 'oliver'),
      ]);
      engine.record('eliot', 'james', MatchOutcome.aWins);
      engine.record('james', 'oliver', MatchOutcome.aWins);
      engine.record('eliot', 'oliver', MatchOutcome.tie);
      return engine;
    }

    test('toJson produces expected structure', () {
      final json = _buildEngine().toJson();
      expect(json['version'], 1);
      expect(json['items'], isA<List>());
      expect(json['history'], isA<List>());
      expect((json['history'] as List).length, 3);
      expect(json.containsKey('isConverged'), isTrue);
    });

    test('fromJson with replay produces identical rankings', () {
      final original = _buildEngine();
      final json = original.toJson();
      final restored = EloEngine.fromJson(json);
      final origRanks = original.rankings.map((i) => i.id).toList();
      final restRanks = restored.rankings.map((i) => i.id).toList();
      expect(restRanks, equals(origRanks));
    });

    test('fromJson with skipReplay uses stored ratings', () {
      final original = _buildEngine();
      final json = original.toJson();
      final restored = EloEngine.fromJson(json, skipReplay: true);
      // Ratings should match stored values exactly
      for (final item in original.rankings) {
        final restoredItem =
            restored.rankings.firstWhere((i) => i.id == item.id);
        expect(restoredItem.rating, closeTo(item.rating, 0.001));
      }
    });

    test('fromJson replay and skipReplay produce same ranking order', () {
      final original = _buildEngine();
      final json = original.toJson();
      final replayed = EloEngine.fromJson(json);
      final skipped = EloEngine.fromJson(json, skipReplay: true);
      expect(
        replayed.rankings.map((i) => i.id).toList(),
        equals(skipped.rankings.map((i) => i.id).toList()),
      );
    });

    test('undo is available after fromJson (history preserved)', () {
      final original = _buildEngine();
      final json = original.toJson();
      final restored = EloEngine.fromJson(json);
      final matchCountBefore = restored.rankings
          .map((i) => i.matchCount)
          .reduce((a, b) => a + b);
      restored.undo();
      final matchCountAfter = restored.rankings
          .map((i) => i.matchCount)
          .reduce((a, b) => a + b);
      // Undo removed one match, so total matchCount should decrease.
      expect(matchCountAfter, lessThan(matchCountBefore));
    });
  });

  group('Edge cases', () {
    test('N=2: single possible pair', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      final proposal = engine.nextMatch()!;
      expect({proposal.itemA.id, proposal.itemB.id}, equals({'a', 'b'}));
    });
  });

  group('EloEngine.compareAlgorithms', () {
    EloEngine _buildEngine() {
      final engine = EloEngine(items: [
        EloItem(id: 'a'),
        EloItem(id: 'b'),
        EloItem(id: 'c'),
        EloItem(id: 'd'),
      ]);
      engine.record('a', 'b', MatchOutcome.aWins);
      engine.record('a', 'c', MatchOutcome.aWins);
      engine.record('a', 'd', MatchOutcome.aWins);
      engine.record('b', 'c', MatchOutcome.aWins);
      engine.record('b', 'd', MatchOutcome.aWins);
      engine.record('c', 'd', MatchOutcome.aWins);
      return engine;
    }

    test('returns non-null live and all 6 batch rankings', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.eloRanking, isNotNull);
      expect(result.glicko2Ranking, isNotNull);
      expect(result.bordaRanking, isNotNull);
      expect(result.copelandRanking, isNotNull);
      expect(result.pageRankRanking, isNotNull);
      expect(result.markovRanking, isNotNull);
      expect(result.schulzeRanking, isNotNull);
      expect(result.rankedPairsRanking, isNotNull);
    });

    test('borda winner is a (most wins)', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.bordaRanking!.first.id, 'a');
    });

    test('glicko2Ranking reflects winner (a is ranked first)', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.glicko2Ranking!.first.id, 'a');
    });

    test('interAlgorithmKendallTau is in [-1.0, 1.0]', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.interAlgorithmKendallTau, greaterThanOrEqualTo(-1.0));
      expect(result.interAlgorithmKendallTau, lessThanOrEqualTo(1.0));
    });

    test('consensusRanking has correct length', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.consensusRanking.length, 4);
    });

    test('divergences has one entry per item', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.divergences.length, 4);
    });

    test('Part 2b algorithms return non-null rankings', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.bradleyTerryRanking, isNotNull);
      expect(result.trueskillRanking, isNotNull);
      expect(result.thurstoneRanking, isNotNull);
      expect(result.springRankRanking, isNotNull);
    });

    test('Part 2c algorithms return non-null results', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.hodge, isNotNull);
      expect(result.serialRank, isNotNull);
      expect(result.matrixFactorization, isNotNull);
    });

    test('hodge gradientRanking winner is a', () {
      final result = _buildEngine().compareAlgorithms();
      expect(result.hodge!.gradientRanking.first.id, 'a');
    });
  });
}
