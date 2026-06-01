import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';

/// Build a session whose item ratings encode the given rank order
/// (rankedIds[0] is rank 0 / best). Ratings are spaced by 100.
EloSession sessionFromRanking(List<String> rankedIds, {String? participantId}) {
  final n = rankedIds.length;
  final items = <EloItem>[
    for (var i = 0; i < n; i++)
      EloItem(id: rankedIds[i], rating: ((n - i) * 100).toDouble()),
  ];
  return EloSession(
    participantId: participantId,
    items: items,
    history: const [],
  );
}

void main() {
  group('EloSession', () {
    test('auto-generates sessionId when not provided', () {
      final s = EloSession(items: const [], history: const []);
      expect(s.sessionId, isNotEmpty);
      expect(s.sessionId, startsWith('session_'));
    });

    test('uses provided sessionId verbatim', () {
      final s = EloSession(
          sessionId: 'my-id', items: const [], history: const []);
      expect(s.sessionId, equals('my-id'));
    });

    test('defaults to standalone sync mode', () {
      final s = EloSession(items: const [], history: const []);
      expect(s.syncMode, equals(SyncMode.standalone));
    });

    test('JSON round-trip preserves all fields', () {
      final original = EloSession(
        sessionId: 'sess-1',
        participantId: 'alice',
        items: [
          EloItem(id: 'a', rating: 1234.5, matchCount: 5),
          EloItem(id: 'b', rating: 1100.0, matchCount: 3),
        ],
        history: [
          EloMatch(
            idA: 'a',
            idB: 'b',
            outcome: MatchOutcome.aWins,
            timestamp: DateTime.fromMillisecondsSinceEpoch(1711000000 * 1000),
          ),
        ],
      );
      final restored = EloSession.fromJson(original.toJson());
      expect(restored.sessionId, equals('sess-1'));
      expect(restored.participantId, equals('alice'));
      expect(restored.syncMode, equals(SyncMode.standalone));
      expect(restored.items.length, equals(2));
      expect(restored.items[0].id, equals('a'));
      expect(restored.items[0].rating, closeTo(1234.5, 0.001));
      expect(restored.history.length, equals(1));
      expect(restored.history[0].outcome, equals(MatchOutcome.aWins));
    });
  });

  group('EloEngine.snapshot', () {
    test('captures items and history with optional participantId', () {
      final engine = EloEngine(items: [
        EloItem(id: 'a'),
        EloItem(id: 'b'),
        EloItem(id: 'c'),
      ]);
      engine.record('a', 'b', MatchOutcome.aWins);
      engine.record('a', 'c', MatchOutcome.aWins);
      engine.record('b', 'c', MatchOutcome.bWins);

      final session = engine.snapshot(participantId: 'alice');
      expect(session.participantId, equals('alice'));
      expect(session.items.length, equals(3));
      expect(session.history.length, equals(3));
      expect(session.syncMode, equals(SyncMode.standalone));
    });

    test('history getter is read-only', () {
      final engine = EloEngine(items: [EloItem(id: 'a'), EloItem(id: 'b')]);
      engine.record('a', 'b', MatchOutcome.aWins);
      expect(() => engine.history.add(engine.history[0]),
          throwsUnsupportedError);
    });
  });

  group('EloMerge.combine', () {
    test('throws on empty session list', () {
      expect(() => EloMerge.combine([]), throwsArgumentError);
    });

    test('throws on mismatched item ID sets', () {
      final s1 = sessionFromRanking(['a', 'b', 'c']);
      final s2 = sessionFromRanking(['a', 'b', 'd']);
      expect(() => EloMerge.combine([s1, s2]), throwsArgumentError);
    });

    test('returns empty list when sessions contain no items', () {
      final s = EloSession(items: const [], history: const []);
      expect(EloMerge.combine([s]), isEmpty);
    });

    test('single session returns its ranking with full agreement', () {
      final session = sessionFromRanking(['a', 'b', 'c']);
      final merged = EloMerge.combine([session]);
      expect(merged.map((r) => r.item.id), equals(['a', 'b', 'c']));
      for (final r in merged) {
        expect(r.agreement, equals(1.0));
        expect(r.ranksByParticipant.length, equals(1));
      }
    });

    test('single-item input has agreement 1.0', () {
      final s1 = sessionFromRanking(['a']);
      final s2 = sessionFromRanking(['a']);
      final merged = EloMerge.combine([s1, s2]);
      expect(merged.length, equals(1));
      expect(merged[0].agreement, equals(1.0));
    });

    test('identical rankings: every item has agreement 1.0', () {
      final s1 = sessionFromRanking(['a', 'b', 'c', 'd']);
      final s2 = sessionFromRanking(['a', 'b', 'c', 'd']);
      final merged = EloMerge.combine([s1, s2]);
      expect(merged.map((r) => r.item.id), equals(['a', 'b', 'c', 'd']));
      for (final r in merged) {
        expect(r.agreement, equals(1.0));
      }
    });

    test('reversed rankings: extremes have agreement 0.0', () {
      final s1 = sessionFromRanking(['a', 'b', 'c', 'd']);
      final s2 = sessionFromRanking(['d', 'c', 'b', 'a']);
      final merged = EloMerge.combine([s1, s2]);
      final byId = {for (final r in merged) r.item.id: r};
      // a: ranks [0, 3]; d: ranks [3, 0] → spread 3, n=4 → agreement 0.0
      expect(byId['a']!.agreement, equals(0.0));
      expect(byId['d']!.agreement, equals(0.0));
      // b/c: ranks [1, 2] / [2, 1] → spread 1, n=4 → agreement 1 - 1/3
      expect(byId['b']!.agreement, closeTo(2.0 / 3.0, 1e-9));
      expect(byId['c']!.agreement, closeTo(2.0 / 3.0, 1e-9));
    });

    test('harmonic mean penalizes one-sided rankings (PRD asymmetric case)',
        () {
      // P1: A B C D E (consistent A-first)
      // P2: E A B C D (E loved by P2, hated by P1)
      // HM should put E *behind* C since one #1 + one near-last = inconsistency.
      final s1 = sessionFromRanking(['A', 'B', 'C', 'D', 'E']);
      final s2 = sessionFromRanking(['E', 'A', 'B', 'C', 'D']);
      final merged =
          EloMerge.combine([s1, s2], strategy: MergeStrategy.harmonicMean);
      expect(
        merged.map((r) => r.item.id).toList(),
        equals(['A', 'B', 'C', 'E', 'D']),
      );
      // E has zero agreement (ranks [4, 0]); the rest have 1 - 1/4 = 0.75.
      final byId = {for (final r in merged) r.item.id: r};
      expect(byId['E']!.agreement, equals(0.0));
      expect(byId['A']!.agreement, equals(0.75));
      expect(byId['D']!.agreement, equals(0.75));
    });

    test('arithmetic mean does not penalize one-sided rankings', () {
      // Same input. AM places E ahead of C: E gets boost from one #1.
      final s1 = sessionFromRanking(['A', 'B', 'C', 'D', 'E']);
      final s2 = sessionFromRanking(['E', 'A', 'B', 'C', 'D']);
      final merged =
          EloMerge.combine([s1, s2], strategy: MergeStrategy.arithmeticMean);
      expect(
        merged.map((r) => r.item.id).toList(),
        equals(['A', 'B', 'E', 'C', 'D']),
      );
    });

    test('minimum strategy bounds score by worst rating', () {
      final s1 = sessionFromRanking(['A', 'B', 'C', 'D', 'E']);
      final s2 = sessionFromRanking(['E', 'A', 'B', 'C', 'D']);
      final merged =
          EloMerge.combine([s1, s2], strategy: MergeStrategy.minimum);
      // Unambiguous top three: A (4) > B (3) > C (2). D and E tie at 1.
      expect(merged[0].item.id, equals('A'));
      expect(merged[0].combinedScore, equals(4.0));
      expect(merged[1].item.id, equals('B'));
      expect(merged[1].combinedScore, equals(3.0));
      expect(merged[2].item.id, equals('C'));
      expect(merged[2].combinedScore, equals(2.0));
      // Last two tied at score 1.0; order between them is unspecified.
      expect(merged[3].combinedScore, equals(1.0));
      expect(merged[4].combinedScore, equals(1.0));
      expect({merged[3].item.id, merged[4].item.id}, equals({'D', 'E'}));
    });

    test('three sessions: harmonic mean across all', () {
      final s1 = sessionFromRanking(['a', 'b', 'c']);
      final s2 = sessionFromRanking(['a', 'b', 'c']);
      final s3 = sessionFromRanking(['a', 'b', 'c']);
      final merged = EloMerge.combine([s1, s2, s3]);
      expect(merged.map((r) => r.item.id), equals(['a', 'b', 'c']));
      for (final r in merged) {
        expect(r.agreement, equals(1.0));
        expect(r.ranksByParticipant.length, equals(3));
      }
    });

    test('ranksByParticipant preserves session order', () {
      final s1 = sessionFromRanking(['a', 'b', 'c']);
      final s2 = sessionFromRanking(['c', 'b', 'a']);
      final merged = EloMerge.combine([s1, s2]);
      final byId = {for (final r in merged) r.item.id: r};
      expect(byId['a']!.ranksByParticipant, equals([0, 2]));
      expect(byId['b']!.ranksByParticipant, equals([1, 1]));
      expect(byId['c']!.ranksByParticipant, equals([2, 0]));
    });

    test('combinedScore math (harmonic mean asymmetric case)', () {
      final s1 = sessionFromRanking(['A', 'B', 'C', 'D', 'E']);
      final s2 = sessionFromRanking(['E', 'A', 'B', 'C', 'D']);
      final merged =
          EloMerge.combine([s1, s2], strategy: MergeStrategy.harmonicMean);
      final byId = {for (final r in merged) r.item.id: r};
      // A: scores [5, 4]; HM = 2*5*4 / (5+4) = 40/9
      expect(byId['A']!.combinedScore, closeTo(40 / 9, 1e-9));
      // E: scores [1, 5]; HM = 2*1*5 / 6 = 10/6
      expect(byId['E']!.combinedScore, closeTo(10 / 6, 1e-9));
    });

    test('end-to-end: two engines → snapshots → merge', () {
      final names = [
        EloItem(id: 'eliot'),
        EloItem(id: 'james'),
        EloItem(id: 'oliver'),
      ];

      // Alice strongly prefers eliot.
      final alice = EloEngine(items: names.map((n) => EloItem(id: n.id)).toList());
      alice.record('eliot', 'james', MatchOutcome.aWins);
      alice.record('eliot', 'oliver', MatchOutcome.aWins);
      alice.record('james', 'oliver', MatchOutcome.aWins);

      // Bob strongly prefers james.
      final bob = EloEngine(items: names.map((n) => EloItem(id: n.id)).toList());
      bob.record('james', 'eliot', MatchOutcome.aWins);
      bob.record('james', 'oliver', MatchOutcome.aWins);
      bob.record('eliot', 'oliver', MatchOutcome.aWins);

      final merged = EloMerge.combine([
        alice.snapshot(participantId: 'alice'),
        bob.snapshot(participantId: 'bob'),
      ]);

      // Both rank oliver last → oliver should be last.
      expect(merged.last.item.id, equals('oliver'));
      // Both rank oliver last with same rank → oliver has perfect agreement.
      expect(merged.last.agreement, equals(1.0));
    });
  });
}
