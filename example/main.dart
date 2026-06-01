// example/main.dart
//
// Interactive baby name ranker demonstrating the full EloEngine lifecycle:
//   - item creation, nextMatch, record, undo, isConverged, compareAlgorithms.
//
// Run from the package root:
//   dart run example/main.dart
//
// Commands during a session:
//   1   left name wins
//   2   right name wins
//   t   tie
//   s   skip (suppresses pair for a few rounds, no rating change)
//   u   undo last recorded match
//   q   quit and show results

import 'dart:io';
import 'package:elo_engine/elo_engine.dart';

void main() {
  final names = [
    'Oliver', 'Eliot', 'James', 'Milo', 'Leo',
    'Isla', 'Aurora', 'Maeve', 'Phoebe', 'Cleo',
  ];

  final engine = EloEngine(
    items: names.map((n) => EloItem(id: n)).toList(),
  );

  stdout.writeln('┌──────────────────────────────────┐');
  stdout.writeln('│        Baby Name Ranker          │');
  stdout.writeln('└──────────────────────────────────┘');
  stdout.writeln('Compare pairs until the ranking converges.');
  stdout.writeln(
      'Commands: 1=left  2=right  t=tie  s=skip  u=undo  q=quit\n');

  loop:
  while (!engine.isConverged) {
    final match = engine.nextMatch();
    if (match == null) break;

    final pct = (match.expectedA * 100).round();
    stdout.write(
      '  [${match.itemA.id}] vs [${match.itemB.id}]'
      '  ($pct% / ${100 - pct}%)  → ',
    );

    final line = stdin.readLineSync()?.trim().toLowerCase() ?? 'q';

    switch (line) {
      case '1':
        engine.record(match.itemA.id, match.itemB.id, MatchOutcome.aWins);
      case '2':
        engine.record(match.itemA.id, match.itemB.id, MatchOutcome.bWins);
      case 't':
        engine.record(match.itemA.id, match.itemB.id, MatchOutcome.tie);
      case 's':
        engine.record(match.itemA.id, match.itemB.id, MatchOutcome.skip);
      case 'u':
        engine.undo();
        stdout.writeln('  ↩ undone');
      case 'q':
        break loop;
      default:
        stdout.writeln('  (unrecognised — try 1, 2, t, s, u, q)');
    }
  }

  _printResults(engine);
}

void _printResults(EloEngine engine) {
  stdout.writeln('\n┌──────────────────────────────────┐');
  stdout.writeln('│          Final Rankings          │');
  stdout.writeln('└──────────────────────────────────┘');

  for (final (i, item) in engine.rankings.indexed) {
    final bar = '█' * ((item.rating - 1100).clamp(0, 300) ~/ 15);
    stdout.writeln(
      '  ${(i + 1).toString().padLeft(2)}. '
      '${item.id.padRight(10)} '
      '${item.rating.round().toString().padLeft(4)}  $bar',
    );
  }

  if (!engine.isConverged) {
    stdout.writeln('\n(session ended before convergence — '
        'run again and keep going for a stable ranking)');
    return;
  }

  stdout.writeln('\n✓ Converged — running algorithm comparison...\n');

  final c = engine.compareAlgorithms();

  stdout.writeln('Consensus ranking (15-algorithm ensemble):');
  for (final (i, item) in c.consensusRanking.indexed) {
    stdout.writeln('  ${(i + 1).toString().padLeft(2)}. ${item.id}');
  }

  final tau = c.interAlgorithmKendallTau.toStringAsFixed(3);
  stdout.writeln('\nInter-algorithm agreement (Kendall τ): $tau');
  if (c.interAlgorithmKendallTau > 0.9) {
    stdout.writeln('  → High agreement: ranking is robust.');
  } else if (c.interAlgorithmKendallTau > 0.6) {
    stdout.writeln('  → Moderate agreement: some ambiguity in middle ranks.');
  } else {
    stdout.writeln(
        '  → Low agreement: preferences may be cyclic or multi-dimensional.');
  }

  final disputed = c.divergences.where((d) => d.rankSpread >= 2).toList();
  if (disputed.isNotEmpty) {
    stdout.writeln('\nMost disputed items (rank spread across algorithms):');
    for (final d in disputed.take(3)) {
      final consensusRank = c.consensusRanking.indexOf(d.item) + 1;
      stdout.writeln('  ${d.item.id.padRight(10)} spread ${d.rankSpread}  '
          '(consensus rank $consensusRank)');
    }
  }

  if (c.hodge != null) {
    final cyclic = (c.hodge!.cyclicMagnitude * 100).round();
    stdout.writeln(
        '\nHodge decomposition: $cyclic% of preference flow is cyclic.');
    if (cyclic > 40) {
      stdout.writeln(
          '  → High cyclic component: preferences have genuine non-transitivity.');
    }
  }
}
