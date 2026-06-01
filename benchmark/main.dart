// benchmark/main.dart
//
// Dependency-free Stopwatch harness for elo_engine hot paths.
//
// Scenarios (each at N=50, 100, 200 items):
//   1. record()                       — single-match append latency
//   2. nextMatch()                    — O(N²) pair scan
//   3. compareAlgorithms() all 15     — full ensemble
//   4. compareAlgorithms() online     — {elo, glicko2, trueskill} only
//   5. compareAlgorithms() elo+borda  — minimal batch
//
// Run from the package root:
//   dart run benchmark/main.dart
//
// For more realistic numbers, compile AOT first:
//   dart compile exe benchmark/main.dart -o bench && ./bench

import 'dart:io';
import 'dart:math';
import 'package:elo_engine/elo_engine.dart';

// Disable convergence so the engine never short-circuits nextMatch().
const _noConvergence = EloConfig(convergenceTau: 2.0);

class BenchResult {
  final String name;
  final int n;
  final Duration min;
  final Duration mean;
  final Duration max;
  final int iterations;
  BenchResult(this.name, this.n, this.min, this.mean, this.max, this.iterations);
}

BenchResult bench(String name, int n, int iterations, void Function() body) {
  // Warmup — let the JIT settle and method inlining happen.
  for (var i = 0; i < 3; i++) {
    body();
  }
  final timesUs = <int>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    timesUs.add(sw.elapsedMicroseconds);
  }
  timesUs.sort();
  final mn = timesUs.first;
  final mx = timesUs.last;
  final mean = timesUs.reduce((a, b) => a + b) ~/ timesUs.length;
  return BenchResult(
    name,
    n,
    Duration(microseconds: mn),
    Duration(microseconds: mean),
    Duration(microseconds: mx),
    iterations,
  );
}

/// Build an engine with `n` items and `n * matchesPerItem` deterministic
/// matches. Lower-indexed items are stronger, so there's a genuine skill
/// signal for the ranking algorithms to recover.
EloEngine buildEngine(int n,
    {int matchesPerItem = 5, EloConfig config = _noConvergence}) {
  final rng = Random(42);
  final items = [for (var i = 0; i < n; i++) EloItem(id: 'item_$i')];
  final engine = EloEngine(items: items, config: config);
  final totalMatches = n * matchesPerItem;
  for (var i = 0; i < totalMatches; i++) {
    final a = rng.nextInt(n);
    var b = rng.nextInt(n);
    while (b == a) {
      b = rng.nextInt(n);
    }
    // Lower index = stronger. Outcome is probabilistic but skewed.
    final pAWins = 0.5 + ((b - a).toDouble() / n) * 0.4;
    final outcome =
        rng.nextDouble() < pAWins ? MatchOutcome.aWins : MatchOutcome.bWins;
    engine.record('item_$a', 'item_$b', outcome);
  }
  return engine;
}

EloConfig _subsetConfig(Set<AlgorithmId> enabled) => EloConfig(
      convergenceTau: 2.0,
      enabledAlgorithms: enabled,
    );

void main() {
  print('elo_engine benchmarks');
  print('  seed: rng(42)');
  print('  matches per item: 5');
  print('  dart: ${Platform.version.split(" ").first}');
  print('');

  final results = <BenchResult>[];

  // 1. record() — hot path during a session.
  for (final n in [50, 100, 200]) {
    final engine = buildEngine(n);
    final rng = Random(123);
    results.add(bench('record()', n, 500, () {
      final a = rng.nextInt(n);
      var b = rng.nextInt(n);
      while (b == a) {
        b = rng.nextInt(n);
      }
      engine.record('item_$a', 'item_$b',
          rng.nextBool() ? MatchOutcome.aWins : MatchOutcome.bWins);
    }));
  }

  // 2. nextMatch() — O(N²) pair scan + recency lookup.
  for (final n in [50, 100, 200]) {
    final engine = buildEngine(n);
    results.add(bench('nextMatch()', n, 200, () {
      engine.nextMatch();
    }));
  }

  // 3. compareAlgorithms() — full 15-algorithm ensemble.
  for (final n in [50, 100, 200]) {
    final engine = buildEngine(n);
    results.add(bench('compareAlgorithms() all-15', n, 5, () {
      engine.compareAlgorithms();
    }));
  }

  // 4. compareAlgorithms() with online-only subset — no PairwiseMatrix.
  for (final n in [50, 100, 200]) {
    final engine = buildEngine(n,
        config: _subsetConfig({
          AlgorithmId.elo,
          AlgorithmId.glicko2,
          AlgorithmId.trueskill,
        }));
    results.add(bench('compareAlgorithms() online-only', n, 100, () {
      engine.compareAlgorithms();
    }));
  }

  // 5. compareAlgorithms() with ELO + Borda — minimal batch pipeline.
  for (final n in [50, 100, 200]) {
    final engine = buildEngine(n,
        config: _subsetConfig({AlgorithmId.elo, AlgorithmId.borda}));
    results.add(bench('compareAlgorithms() elo+borda', n, 50, () {
      engine.compareAlgorithms();
    }));
  }

  _printTable(results);
  _checkPrdTargets(results);
}

void _printTable(List<BenchResult> results) {
  final nameW = results.map((r) => r.name.length).reduce(max);
  print('  ${"Scenario".padRight(nameW)}  ${"N".padLeft(4)}'
      '  ${"min".padLeft(10)}  ${"mean".padLeft(10)}  ${"max".padLeft(10)}'
      '  iters');
  print('  ${"-" * nameW}  ${"-" * 4}  ${"-" * 10}  ${"-" * 10}  ${"-" * 10}'
      '  -----');
  for (final r in results) {
    print('  ${r.name.padRight(nameW)}  ${r.n.toString().padLeft(4)}'
        '  ${_fmt(r.min).padLeft(10)}  ${_fmt(r.mean).padLeft(10)}'
        '  ${_fmt(r.max).padLeft(10)}  ${r.iterations.toString().padLeft(5)}');
  }
  print('');
}

String _fmt(Duration d) {
  final us = d.inMicroseconds;
  if (us < 1000) return '$us µs';
  if (us < 1000000) return '${(us / 1000).toStringAsFixed(2)}ms';
  return '${(us / 1000000).toStringAsFixed(2)}s';
}

void _checkPrdTargets(List<BenchResult> results) {
  // Regression guards for the developer-time (JIT / `dart run`) path. AOT
  // builds are typically ~1.5× slower for this kind of polymorphic
  // numerical code — the JIT's profile-guided type specialization beats
  // AOT here. These targets are not promises; they exist so perf
  // regressions show up as a visible FAIL in CI.
  print('Regression guards (N=200, JIT):');
  final nextAt200 =
      results.where((r) => r.name == 'nextMatch()' && r.n == 200).first;
  final cmpAt200 = results
      .where((r) => r.name == 'compareAlgorithms() all-15' && r.n == 200)
      .first;
  final onlineAt200 = results
      .where(
          (r) => r.name == 'compareAlgorithms() online-only' && r.n == 200)
      .first;
  final bordaAt200 = results
      .where(
          (r) => r.name == 'compareAlgorithms() elo+borda' && r.n == 200)
      .first;
  final nextOk = nextAt200.mean.inMicroseconds < 5000;
  final cmpOk = cmpAt200.mean.inMicroseconds < 750000;
  final onlineOk = onlineAt200.mean.inMicroseconds < 10000;
  final bordaOk = bordaAt200.mean.inMicroseconds < 10000;
  print('  nextMatch() < 5ms:                       '
      '${nextOk ? "PASS" : "FAIL"}  (mean ${_fmt(nextAt200.mean)})');
  print('  compareAlgorithms() all-15 < 750ms:      '
      '${cmpOk ? "PASS" : "FAIL"}  (mean ${_fmt(cmpAt200.mean)})');
  print('  compareAlgorithms() online-only < 10ms:  '
      '${onlineOk ? "PASS" : "FAIL"}  (mean ${_fmt(onlineAt200.mean)})');
  print('  compareAlgorithms() elo+borda < 10ms:    '
      '${bordaOk ? "PASS" : "FAIL"}  (mean ${_fmt(bordaAt200.mean)})');
  if (!nextOk || !cmpOk || !onlineOk || !bordaOk) {
    print('');
    print('One or more regression guards tripped — investigate.');
    exitCode = 1;
  }
}
