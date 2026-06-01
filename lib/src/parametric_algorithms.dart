import 'dart:math';
import 'pairwise_matrix.dart';

// ── Bradley-Terry ─────────────────────────────────────────────────────────────

/// Bradley-Terry maximum-likelihood ranking via Zermelo's iterative algorithm.
///
/// Treats each tie as 0.5 wins for each side. Items with no wins receive
/// parameter value 0 and rank last. Converges in ≤ 1000 iterations.
List<String> bradleyTerryRanking(PairwiseMatrix matrix) {
  final n = matrix.n;
  if (n == 0) return [];
  if (n == 1) return List.of(matrix.ids);

  // w[i] = total wins for item i (ties count 0.5 each)
  final wins = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i == j) continue;
      wins[i] += matrix.wins[i][j] + 0.5 * matrix.ties[i][j];
    }
  }

  // If no non-skip matches exist, return ids in original order.
  final totalWins = wins.fold(0.0, (a, b) => a + b);
  if (totalWins == 0.0) return List.of(matrix.ids);

  // Precompute total comparisons between each pair — used every iteration.
  final nij = List.generate(
      n, (i) => List.generate(n, (j) => matrix.matchesBetween(i, j)));

  // Zermelo iterative MLE: p_i ← w_i / Σ_j n_ij/(p_i + p_j)
  var params = List<double>.filled(n, 1.0);

  for (var iter = 0; iter < 1000; iter++) {
    final newParams = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      var denom = 0.0;
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        if (nij[i][j] > 0) denom += nij[i][j] / (params[i] + params[j]);
      }
      newParams[i] = denom == 0.0 ? 0.0 : wins[i] / denom;
    }

    // Normalize so parameters sum to 1 (prevents scale drift).
    final total = newParams.fold(0.0, (a, b) => a + b);
    if (total > 0) {
      for (var i = 0; i < n; i++) newParams[i] /= total;
    }

    // Check convergence.
    var maxChange = 0.0;
    for (var i = 0; i < n; i++) {
      maxChange = max(maxChange, (newParams[i] - params[i]).abs());
    }
    params = newParams;
    if (maxChange < 1e-6) break;
  }

  final indexed = List.generate(n, (i) => i);
  indexed.sort((a, b) => params[b].compareTo(params[a]));
  return indexed.map((i) => matrix.ids[i]).toList();
}

// ── Thurstone Case V ──────────────────────────────────────────────────────────

/// Thurstone Case V ranking: mean of probit-transformed win rates.
///
/// For each observed pair (i, j), computes z_ij = Φ⁻¹(p_ij) where
/// p_ij = (wins[i][j] + 0.5·ties[i][j]) / totalComparisons(i,j),
/// clipped to [0.001, 0.999] to avoid infinite probit values.
/// Score for item i = mean z_ij over all opponents j with shared comparisons.
/// Items with no comparisons score 0 and sort to the middle.
List<String> thurstoneRanking(PairwiseMatrix matrix) {
  final n = matrix.n;
  if (n == 0) return [];
  if (n == 1) return List.of(matrix.ids);

  final scores = List<double>.filled(n, 0.0);
  final counts = List<int>.filled(n, 0);

  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i == j) continue;
      final nij = matrix.matchesBetween(i, j);
      if (nij == 0) continue;
      final pij =
          ((matrix.wins[i][j] + 0.5 * matrix.ties[i][j]) / nij)
              .clamp(0.001, 0.999);
      scores[i] += _probit(pij);
      counts[i]++;
    }
  }

  for (var i = 0; i < n; i++) {
    if (counts[i] > 0) scores[i] /= counts[i];
  }

  final indexed = List.generate(n, (i) => i);
  indexed.sort((a, b) => scores[b].compareTo(scores[a]));
  return indexed.map((i) => matrix.ids[i]).toList();
}

/// Inverse normal CDF (probit) via rational approximation.
/// Abramowitz & Stegun 26.2.23. Max |error| < 4.5×10⁻⁴ for all p ∈ (0, 1).
double _probit(double p) {
  if (p <= 0.0 || p >= 1.0) {
    throw ArgumentError.value(p, 'p', 'must be strictly between 0 and 1');
  }
  const c0 = 2.515517, c1 = 0.802853, c2 = 0.010328;
  const d1 = 1.432788, d2 = 0.189269, d3 = 0.001308;
  final pClamped = p < 0.5 ? p : 1.0 - p;
  final t = sqrt(-2.0 * log(pClamped));
  final result = t -
      (c0 + c1 * t + c2 * t * t) /
          (1.0 + d1 * t + d2 * t * t + d3 * t * t * t);
  return p < 0.5 ? -result : result;
}

// ── SpringRank ────────────────────────────────────────────────────────────────

/// SpringRank physics model: items are nodes on a 1D axis; each comparison is
/// a spring with rest length 1. Equilibrium positions minimise total spring
/// tension (De Bacco et al. 2018).
///
/// Solves the graph-Laplacian system (L + αI)·s = b via Gaussian elimination,
/// where α = 0.001 regularisation ensures a unique solution even for isolated
/// nodes. Sort by score descending.
List<String> springRankRanking(PairwiseMatrix matrix) {
  final n = matrix.n;
  if (n == 0) return [];
  if (n == 1) return List.of(matrix.ids);

  const alpha = 0.001; // regularisation prevents singular Laplacian

  // Build graph Laplacian L and right-hand-side b.
  // C[i][j] = wins[i][j] + 0.5·ties[i][j]  (i beat j this many times)
  final L = List.generate(n, (_) => List<double>.filled(n, 0.0));
  final b = List<double>.filled(n, 0.0);

  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i == j) continue;
      final cij = matrix.wins[i][j] + 0.5 * matrix.ties[i][j];
      final cji = matrix.wins[j][i] + 0.5 * matrix.ties[j][i];
      L[i][i] += cij + cji;
      L[i][j] -= cij + cji;
      b[i] += cij - cji;
    }
  }

  // Add regularisation to diagonal (ensures unique solution for isolated nodes).
  for (var i = 0; i < n; i++) {
    L[i][i] += alpha;
  }

  final s = _solveLinearSystem(L, b);

  final indexed = List.generate(n, (i) => i);
  indexed.sort((i, j) => s[j].compareTo(s[i]));
  return indexed.map((i) => matrix.ids[i]).toList();
}

/// Gaussian elimination with partial pivoting. Returns the solution vector x
/// for the square system A·x = b. Near-zero pivots are treated as zero (no
/// update) — the α regularisation in springRankRanking prevents this in practice.
List<double> _solveLinearSystem(List<List<double>> A, List<double> b) {
  final n = A.length;
  // Build augmented matrix [A | b].
  final aug = List.generate(n, (i) => [...A[i], b[i]]);

  for (var col = 0; col < n; col++) {
    // Partial pivoting: swap the row with the largest absolute value in col.
    var maxRow = col;
    for (var row = col + 1; row < n; row++) {
      if (aug[row][col].abs() > aug[maxRow][col].abs()) maxRow = row;
    }
    final tmp = aug[col];
    aug[col] = aug[maxRow];
    aug[maxRow] = tmp;

    final pivot = aug[col][col];
    if (pivot.abs() < 1e-12) continue; // near-singular column, skip

    for (var row = col + 1; row < n; row++) {
      final factor = aug[row][col] / pivot;
      for (var k = col; k <= n; k++) {
        aug[row][k] -= factor * aug[col][k];
      }
    }
  }

  // Back-substitution.
  final x = List<double>.filled(n, 0.0);
  for (var i = n - 1; i >= 0; i--) {
    var sum = aug[i][n];
    for (var j = i + 1; j < n; j++) sum -= aug[i][j] * x[j];
    x[i] = aug[i][i].abs() < 1e-12 ? 0.0 : sum / aug[i][i];
  }
  return x;
}

// ── HodgeRank ─────────────────────────────────────────────────────────────────

/// HodgeRank: Helmholtz–Hodge decomposition of pairwise comparison flow.
///
/// Models comparison outcomes as a flow on the comparison graph. Finds the
/// gradient component (a consistent ranking) that best explains the observed
/// flow via weighted least squares on the graph Laplacian with uniform edge
/// weights (1 per observed pair).
///
/// Returns:
///   ranking          — items sorted by gradient score descending.
///   cyclicMagnitude  — ∈ [0,1]; fraction of flow energy unexplained by ranking.
///                      0 = perfectly consistent; 1 = pure cyclic flow.
///   harmonicMagnitude — ∈ [0,1]; fraction of item pairs not yet compared.
///                       0 = all pairs compared; 1 = no comparisons.
({List<String> ranking, double cyclicMagnitude, double harmonicMagnitude})
    hodgeRanking(PairwiseMatrix matrix) {
  final n = matrix.n;
  if (n == 0) {
    return (ranking: [], cyclicMagnitude: 0.0, harmonicMagnitude: 0.0);
  }
  if (n == 1) {
    return (
      ranking: List.of(matrix.ids),
      cyclicMagnitude: 0.0,
      harmonicMagnitude: 0.0,
    );
  }

  const alpha = 0.001;

  // W[i][j] = win rate (0.5 for unobserved). Centred: C[i][j] = W[i][j] − 0.5.
  // Unobserved pairs → C[i][j] = 0, contributing nothing to b or the residual.
  final W = matrix.winRateMatrix;

  // Uniform-weight Laplacian: L[i][i] = degree; L[i][j] = −1 if compared.
  // b[i] = Σ_j (W[i][j] − 0.5)  (unobserved pairs contribute 0).
  final L = List.generate(n, (_) => List<double>.filled(n, 0.0));
  final b = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (i == j) continue;
      if (matrix.matchesBetween(i, j) > 0) {
        L[i][i] += 1.0;
        L[i][j] -= 1.0;
        b[i] += W[i][j] - 0.5;
      }
    }
  }
  for (var i = 0; i < n; i++) L[i][i] += alpha;

  final s = _solveLinearSystem(L, b);

  // Cyclic magnitude: normalised residual energy over observed pairs only.
  var flowSumSq = 0.0;
  var residualSumSq = 0.0;
  for (var i = 0; i < n - 1; i++) {
    for (var j = i + 1; j < n; j++) {
      if (matrix.matchesBetween(i, j) == 0) continue;
      final fij = W[i][j] - 0.5;
      final rij = fij - (s[i] - s[j]);
      flowSumSq += fij * fij;
      residualSumSq += rij * rij;
    }
  }
  final cyclicMagnitude = flowSumSq < 1e-12
      ? 0.0
      : sqrt(residualSumSq / flowSumSq).clamp(0.0, 1.0);

  // Harmonic magnitude: fraction of missing pairs.
  final totalPairs = n * (n - 1) ~/ 2;
  var pairsCompared = 0;
  for (var i = 0; i < n - 1; i++) {
    for (var j = i + 1; j < n; j++) {
      if (matrix.matchesBetween(i, j) > 0) pairsCompared++;
    }
  }
  final harmonicMagnitude =
      totalPairs == 0 ? 0.0 : 1.0 - pairsCompared / totalPairs;

  final indexed = List.generate(n, (i) => i)
    ..sort((i, j) => s[j].compareTo(s[i]));
  return (
    ranking: indexed.map((i) => matrix.ids[i]).toList(),
    cyclicMagnitude: cyclicMagnitude,
    harmonicMagnitude: harmonicMagnitude,
  );
}

// ── SerialRank ────────────────────────────────────────────────────────────────

/// SerialRank: ranks items by average win rate across all opponents.
///
/// Uses [PairwiseMatrix.winRateMatrix] which returns 0.5 for unobserved pairs,
/// pulling items toward the midpoint when they have few comparisons.
///
/// score[i] = (Σ_{j≠i} W[i][j]) / (n − 1)
///
/// Rankability ∈ [0,1] = fraction of observed pairs where the higher-ranked
/// item actually wins more often. 1.0 = perfectly consistent; lower values
/// indicate cyclic or multi-dimensional preferences.
({List<String> ranking, double rankability}) serialRanking(
    PairwiseMatrix matrix) {
  final n = matrix.n;
  if (n == 0) return (ranking: [], rankability: 1.0);
  if (n == 1) return (ranking: List.of(matrix.ids), rankability: 1.0);

  final W = matrix.winRateMatrix;

  final scores = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    var sum = 0.0;
    for (var j = 0; j < n; j++) {
      if (i != j) sum += W[i][j];
    }
    scores[i] = sum / (n - 1);
  }

  final indexed = List.generate(n, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));
  final ranking = indexed.map((i) => matrix.ids[i]).toList();

  // rank[i] = 0-indexed position of item i in the sorted ranking (0 = best).
  final rank = List.filled(n, 0);
  for (var pos = 0; pos < n; pos++) rank[indexed[pos]] = pos;

  // Rankability = concordant observed pairs / total observed pairs.
  var concordant = 0;
  var observed = 0;
  for (var i = 0; i < n - 1; i++) {
    for (var j = i + 1; j < n; j++) {
      if (matrix.matchesBetween(i, j) == 0) continue;
      observed++;
      if ((rank[i] < rank[j] && W[i][j] > 0.5) ||
          (rank[i] > rank[j] && W[j][i] > 0.5)) {
        concordant++;
      }
    }
  }

  return (
    ranking: ranking,
    rankability: observed == 0 ? 1.0 : concordant / observed,
  );
}

// ── Matrix Factorization ───────────────────────────────────────────────────────

/// Low-rank approximation of the pairwise comparison matrix via truncated SVD.
///
/// Decomposes the centred antisymmetric win-rate matrix C (C[i][j] = W[i][j]−0.5,
/// which is 0 for unobserved pairs) by computing up to 3 eigenvectors of
/// M = CᵀC (positive semi-definite, symmetric) via power iteration + deflation.
///
/// Returns:
///   ranking          — items sorted by their projection onto the top singular
///                      vector: score[i] = Σ_j C[i][j]·v₁[j].
///   bestRank         — smallest k ∈ [1, min(3, n−1)] such that the top-k
///                      eigenvalues explain ≥ 80% of trace(M); k=min(3,n-1)
///                      if no threshold is met. 1 when no comparisons.
///   explainedVariance — fraction of trace(M) explained by the top-bestRank
///                      eigenvalues. Clamped to [0,1].
({List<String> ranking, int bestRank, double explainedVariance})
    matrixFactorizationRanking(PairwiseMatrix matrix) {
  final n = matrix.n;
  if (n == 0) return (ranking: [], bestRank: 1, explainedVariance: 0.0);
  if (n == 1) {
    return (
      ranking: List.of(matrix.ids),
      bestRank: 1,
      explainedVariance: 1.0,
    );
  }

  final W = matrix.winRateMatrix;

  // C[i][j] = W[i][j] − 0.5 (antisymmetric; 0 for unobserved pairs).
  final C = List.generate(
      n, (i) => List.generate(n, (j) => i == j ? 0.0 : W[i][j] - 0.5));

  // M = CᵀC: M[i][j] = Σ_k C[k][i] · C[k][j].
  final M = List.generate(
      n,
      (i) => List.generate(n, (j) {
            var sum = 0.0;
            for (var k = 0; k < n; k++) sum += C[k][i] * C[k][j];
            return sum;
          }));

  var traceM = 0.0;
  for (var i = 0; i < n; i++) traceM += M[i][i];

  if (traceM < 1e-12) {
    return (ranking: List.of(matrix.ids), bestRank: 1, explainedVariance: 0.0);
  }

  // Compute top-k eigenpairs via power iteration + deflation.
  final maxK = min(3, n - 1);
  final lambdas = <double>[];
  final vectors = <List<double>>[];
  var mCurrent = M;

  for (var k = 0; k < maxK; k++) {
    final r = _powerIterate(mCurrent);
    if (r.eigenvalue < 1e-12) break;
    lambdas.add(r.eigenvalue);
    vectors.add(r.eigenvector);
    mCurrent = _deflate(mCurrent, r.eigenvector, r.eigenvalue);
  }

  if (lambdas.isEmpty) {
    return (ranking: List.of(matrix.ids), bestRank: 1, explainedVariance: 0.0);
  }

  // bestRank: smallest k where cumulative eigenvalues / trace ≥ 0.8.
  var cumulative = 0.0;
  var bestRank = maxK;
  for (var k = 0; k < lambdas.length; k++) {
    cumulative += lambdas[k] / traceM;
    if (cumulative >= 0.8) {
      bestRank = k + 1;
      break;
    }
  }
  // Power iteration may terminate early with fewer than maxK eigenvectors.
  if (bestRank > lambdas.length) bestRank = lambdas.length;
  final explainedVariance =
      (lambdas.take(bestRank).fold(0.0, (s, l) => s + l) / traceM)
          .clamp(0.0, 1.0);

  // Consensus ranking: score[i] = (C · v₁)[i].
  final v1 = vectors[0];
  final scoreVec = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      scoreVec[i] += C[i][j] * v1[j];
    }
  }

  final indexed = List.generate(n, (i) => i)
    ..sort((i, j) => scoreVec[j].compareTo(scoreVec[i]));
  return (
    ranking: indexed.map((i) => matrix.ids[i]).toList(),
    bestRank: bestRank,
    explainedVariance: explainedVariance,
  );
}

/// Power iteration: dominant eigenpair of symmetric positive semi-definite
/// matrix [m]. Runs 100 iterations from a uniform starting vector.
({double eigenvalue, List<double> eigenvector}) _powerIterate(
    List<List<double>> m) {
  final n = m.length;
  var v = List<double>.filled(n, 1.0 / sqrt(n.toDouble()));
  for (var iter = 0; iter < 100; iter++) {
    final mv = List<double>.filled(n, 0.0);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) mv[i] += m[i][j] * v[j];
    }
    var norm = 0.0;
    for (final x in mv) norm += x * x;
    norm = sqrt(norm);
    if (norm < 1e-12) break;
    for (var i = 0; i < n; i++) v[i] = mv[i] / norm;
  }
  // Rayleigh quotient: λ = vᵀMv.
  var eigenvalue = 0.0;
  for (var i = 0; i < n; i++) {
    var row = 0.0;
    for (var j = 0; j < n; j++) row += m[i][j] * v[j];
    eigenvalue += v[i] * row;
  }
  return (
    eigenvalue: eigenvalue < 0.0 ? 0.0 : eigenvalue,
    eigenvector: v,
  );
}

/// Deflate [m] by subtracting the rank-1 component [eigenvalue]·[v]·[v]ᵀ.
List<List<double>> _deflate(
    List<List<double>> m, List<double> v, double eigenvalue) {
  final n = m.length;
  return List.generate(
      n, (i) => List.generate(n, (j) => m[i][j] - eigenvalue * v[i] * v[j]));
}
