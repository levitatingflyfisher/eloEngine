import 'dart:collection';
import 'dart:math';
import 'pairwise_matrix.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Borda Count (derived from pairwise wins)
// ──────────────────────────────────────────────────────────────────────────────

/// Borda ranking: score = total wins. Higher wins → ranked first.
List<String> bordaRanking(PairwiseMatrix matrix) {
  final n = matrix.n;
  final scores = List.generate(n, (i) =>
      matrix.wins[i].fold(0, (sum, w) => sum + w));
  final indexed = List.generate(n, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));
  return indexed.map((i) => matrix.ids[i]).toList();
}

// ──────────────────────────────────────────────────────────────────────────────
// Copeland's Method
// ──────────────────────────────────────────────────────────────────────────────

/// Copeland ranking: score = (head-to-head wins) − (head-to-head losses) over all pairs.
/// Finds the Condorcet winner when one exists; degrades gracefully through cycles.
List<String> copelandRanking(PairwiseMatrix matrix) {
  final n = matrix.n;
  final scores = List.filled(n, 0);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i == j) continue;
      if (matrix.wins[i][j] > matrix.wins[j][i]) {
        scores[i]++;
      } else if (matrix.wins[j][i] > matrix.wins[i][j]) {
        scores[i]--;
      }
      // equal head-to-head record: 0 contribution
    }
  }
  final indexed = List.generate(n, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));
  return indexed.map((i) => matrix.ids[i]).toList();
}

// ──────────────────────────────────────────────────────────────────────────────
// PageRank
// ──────────────────────────────────────────────────────────────────────────────

/// PageRank on the win graph: each win is a directed edge from loser to winner,
/// weighted by win count. Items beaten by highly-ranked items rank higher.
/// Damping factor 0.85 (standard for convergence in sparse graphs).
List<String> pageRankRanking(
  PairwiseMatrix matrix, {
  double dampingFactor = 0.85,
  int iterations = 100,
}) {
  final n = matrix.n;
  var ranks = List.filled(n, 1.0 / n);

  // outWeight[j] = total losses of j = Σᵢ wins[i][j] (edges leaving j → items that beat j)
  final outWeights = List.generate(n, (j) =>
      List.generate(n, (k) => matrix.wins[k][j].toDouble())
          .fold(0.0, (a, b) => a + b));

  for (var iter = 0; iter < iterations; iter++) {
    final newRanks = List.filled(n, (1.0 - dampingFactor) / n);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (outWeights[j] > 0) {
          newRanks[i] +=
              dampingFactor * ranks[j] * matrix.wins[i][j] / outWeights[j];
        } else {
          // Dangling node: j has never lost; distribute its rank evenly
          newRanks[i] += dampingFactor * ranks[j] / n;
        }
      }
    }
    ranks = newRanks;
  }

  final indexed = List.generate(n, (i) => i)
    ..sort((a, b) => ranks[b].compareTo(ranks[a]));
  return indexed.map((i) => matrix.ids[i]).toList();
}

// ──────────────────────────────────────────────────────────────────────────────
// Markov Chain Stationary Distribution
// ──────────────────────────────────────────────────────────────────────────────

/// Markov ranking: random walk on the win graph without teleportation.
/// Transition from j to i ∝ wins[i][j] (how many times i beat j).
/// Stationary distribution = ranking. Maximum-entropy ranking consistent
/// with pairwise data.
List<String> markovRanking(PairwiseMatrix matrix, {int iterations = 500}) {
  final n = matrix.n;
  var ranks = List.filled(n, 1.0 / n);

  final outWeights = List.generate(n, (j) =>
      List.generate(n, (k) => matrix.wins[k][j].toDouble())
          .fold(0.0, (a, b) => a + b));

  for (var iter = 0; iter < iterations; iter++) {
    final newRanks = List.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (outWeights[j] > 0) {
          newRanks[i] += ranks[j] * matrix.wins[i][j] / outWeights[j];
        } else {
          // Absorbing state: j has never lost; distribute mass evenly
          newRanks[i] += ranks[j] / n;
        }
      }
    }
    // Normalize to keep distribution valid
    final sum = newRanks.fold(0.0, (a, b) => a + b);
    if (sum > 0) {
      for (var i = 0; i < n; i++) {
        ranks[i] = newRanks[i] / sum;
      }
    }
  }

  final indexed = List.generate(n, (i) => i)
    ..sort((a, b) => ranks[b].compareTo(ranks[a]));
  return indexed.map((i) => matrix.ids[i]).toList();
}

// ──────────────────────────────────────────────────────────────────────────────
// Schulze Method (Beatpath)
// ──────────────────────────────────────────────────────────────────────────────

/// Schulze ranking: finds the strongest pairwise beatpath between all items
/// using Floyd-Warshall. Handles cyclic preferences gracefully.
/// Score = number of items this item beats on its strongest beatpath.
List<String> schulzeRanking(PairwiseMatrix matrix) {
  final n = matrix.n;

  // Net win margin: d[i][j] = max(0, wins[i][j] - wins[j][i])
  final d = List.generate(
      n, (i) => List.generate(n, (j) => max(0, matrix.wins[i][j] - matrix.wins[j][i])));

  // Strongest beatpath p[i][j] via Floyd-Warshall.
  // p[i][j] = max over all paths from i to j of (minimum link strength along the path).
  final p = List.generate(n, (i) => List<int>.from(d[i]));
  for (var k = 0; k < n; k++) {
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i != j) {
          p[i][j] = max(p[i][j], min(p[i][k], p[k][j]));
        }
      }
    }
  }

  // Score = number of items j where p[i][j] > p[j][i]
  final scores = List.generate(n, (i) {
    var wins = 0;
    for (var j = 0; j < n; j++) {
      if (i != j && p[i][j] > p[j][i]) wins++;
    }
    return wins;
  });

  final indexed = List.generate(n, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));
  return indexed.map((i) => matrix.ids[i]).toList();
}

// ──────────────────────────────────────────────────────────────────────────────
// Ranked Pairs (Tideman)
// ──────────────────────────────────────────────────────────────────────────────

/// Ranked Pairs ranking: lock pairwise victories strongest-first, skipping any
/// that would create a cycle. Topological sort of the locked DAG = ranking.
List<String> rankedPairsRanking(PairwiseMatrix matrix) {
  final n = matrix.n;

  // Collect all pairwise victories with their net margins.
  final victories = <({int winner, int loser, int margin})>[];
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final net = matrix.wins[i][j] - matrix.wins[j][i];
      if (net > 0) {
        victories.add((winner: i, loser: j, margin: net));
      } else if (net < 0) {
        victories.add((winner: j, loser: i, margin: -net));
      }
      // net == 0: symmetric record, skip
    }
  }

  // Sort by margin descending (strongest victory first).
  victories.sort((a, b) => b.margin.compareTo(a.margin));

  // locked[i] = set of j where i beats j in the locked DAG.
  final locked = List.generate(n, (_) => <int>{});

  for (final v in victories) {
    // Only lock if it doesn't create a cycle (no path from loser back to winner).
    if (!_hasPath(locked, from: v.loser, to: v.winner, n: n)) {
      locked[v.winner].add(v.loser);
    }
  }

  // Topological sort of locked DAG: sources (in-degree 0) come first.
  final inDegree = List.filled(n, 0);
  for (var i = 0; i < n; i++) {
    for (final j in locked[i]) {
      inDegree[j]++;
    }
  }

  final queue = Queue<int>();
  for (var i = 0; i < n; i++) {
    if (inDegree[i] == 0) queue.add(i);
  }

  final result = <String>[];
  while (queue.isNotEmpty) {
    final node = queue.removeFirst();
    result.add(matrix.ids[node]);
    for (final next in locked[node]) {
      if (--inDegree[next] == 0) queue.add(next);
    }
  }

  return result;
}

// BFS reachability check: can we reach [to] from [from] in [graph]?
bool _hasPath(List<Set<int>> graph, {required int from, required int to, required int n}) {
  final visited = <int>{};
  final queue = Queue<int>()..add(from);
  while (queue.isNotEmpty) {
    final node = queue.removeFirst();
    if (node == to) return true;
    if (!visited.add(node)) continue;
    queue.addAll(graph[node]);
  }
  return false;
}
