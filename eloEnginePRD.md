# PRD: `elo_engine`
**Package:** `package:elo_engine` (pub.dev, OpenHearth org)
**Type:** Pure Dart library
**Dependencies:** `dart:math` only (v1); `supabase_flutter` in `sync.dart` only (v2)
**Status:** Tier 1 — build before Baby Names
**Owner:** ISS / OpenHearth

---

## 1. Purpose

Several OpenHearth apps need to take a set of N items and surface a ranked preference order without overwhelming the user. Direct ranking of 50 baby names is paralyzing. Head-to-head matchups ("Eliot or James?") are trivially easy, and pairwise comparison algorithms produce robust global rankings from sparse matchup data.

ELO is the entry point everyone recognizes — the Honda Civic of ranking algorithms. The library is named for it. But the core insight is broader: **the pairwise comparison matrix is a universal substrate**. The user always does the same thing (pick between two items). Fourteen algorithms read that matrix differently, their agreements indicate robust findings, and their disagreements are themselves informative. This library collects the data once and runs the full ensemble at results time.

This library is algorithm and sync only. No UI, no storage, no domain logic.

---

## 2. Scope

**In:** Pairwise comparison data collection, full algorithm ensemble, smart pair selection, convergence signal, multi-participant merge, async and live sync modes, JSON serialization.

**Out:** Persistence (consumer's job), UI, networking outside `sync.dart`, any domain-specific logic.

---

## 3. Versioning

| Version | Scope | Ships With |
|---|---|---|
| v1 | Standalone, single participant, Ghost mode only, zero network | Baby Names v1, Wishlist Ranker |
| v2 | Multi-participant sync (async merge + live session) | Baby Names v2 (couples), Restaurant Chooser |

v2 is strictly additive. v1 consumers never import `sync.dart` and pay no Supabase dependency cost.

---

## 4. Algorithm Ensemble

All algorithms operate on the same pairwise comparison matrix — who beat whom, how many times. The user input is always identical: pick between two items. Algorithms differ only in how they process that matrix.

Note on Borda: its classical form requires full rank orderings as input. Derived from pairwise data it degenerates to win-counting, which is already in the matrix — cheap and still useful.

### 4.1 Algorithm Registry

**Parametric Score Models**
Assume each item has a latent real-valued quality; comparisons are noisy observations of it.

| Algorithm | Update | Description |
|---|---|---|
| **ELO** | Online | Logistic probability model with sequential update rule. Fast, simple, the default live-update algorithm. |
| **Bradley-Terry** | Batch MLE | ELO's probabilistic parent. ELO is online gradient descent on the Bradley-Terry log-likelihood — asymptotically equivalent with sufficient data. Bradley-Terry solves the full MLE exactly (iteratively) rather than approximating with sequential updates. More accurate with sparse data. |
| **Glicko-2** | Online | ELO + uncertainty tracking. Each item carries a rating, a rating deviation (RD — confidence interval), and a volatility parameter tracking rating stability. RD inflates during inactivity. Gives a principled answer to "how much do I trust this rating?" |
| **TrueSkill** | Online | Fully Bayesian. Each item has a Gaussian belief distribution; comparisons update the full distribution via belief propagation. Glicko-2's uncertainty is approximate; TrueSkill's is calibrated. Designed for multiplayer matchmaking, degenerates cleanly to 1v1. |
| **Thurstone Case V** | Batch | Psychophysical model predating ELO by 30 years (1927). Normal distribution instead of logistic — a comparison draws one sample from each item's normal distribution; higher sample wins. Rankings nearly identical to Bradley-Terry in practice, but the framing is more honest: you're sampling from noisy internal representations, not measuring fixed latent quality. |

**Physics / Equilibrium Models**

| Algorithm | Update | Description |
|---|---|---|
| **SpringRank** | Batch | Items are nodes on a 1D axis. Each comparison is a spring — stretched if the lower-ranked item won unexpectedly, compressed otherwise. Equilibrium positions = ranking. MAP estimate under a specific generative model. Handles cycles by minimizing total spring tension rather than forcing strict order. Outperforms ELO and PageRank on real-world dominance hierarchy data. |

**Graph / Network Models**

| Algorithm | Update | Description |
|---|---|---|
| **PageRank** | Batch | Directed win graph; each win is an edge from loser to winner weighted by margin. Items beaten by highly-ranked items rank higher. Works well for sparse comparison graphs where direct comparisons are missing. |
| **Markov Chain Stationary Distribution** | Batch | Random walk on win graph: from item A, transition to item B proportional to how many times B beat A. Stationary distribution = ranking. Maximum entropy ranking consistent with pairwise data. |
| **Copeland's Method** | Batch | Score = wins − losses. Trivially cheap. Finds the Condorcet winner if one exists, degrades gracefully through cycles. Key value: instantly interpretable ("this name beat 47 others and lost to 3") for non-technical users. |

**Spectral / Algebraic Models**

| Algorithm | Update | Description |
|---|---|---|
| **HodgeRank** | Batch | Hodge decomposition applied to the comparison graph. Decomposes observed preferences into three orthogonal components: (1) gradient — the consistent transitive ranking; (2) cyclic — genuine intransitive cycles; (3) harmonic — inconsistency from missing data. The only method that surfaces *where* and *how much* preferences cycle rather than hiding it in a forced linear order. |
| **SerialRank** | Batch | A perfect ranking would produce a step-function pairwise matrix. SerialRank finds the permutation that makes the matrix most like that ideal (eigenvector relaxation). Key output: the second eigenvalue magnitude directly measures how "rankable" the data is. Small value = genuinely multidimensional preferences, no single ranking captures them well. |
| **Win-Rate Matrix Factorization** | Batch | Decomposes the pairwise win-rate matrix W (W[i][j] = fraction of comparisons item i beat item j) into low-rank factors. Rank-1 fit = essentially 1D preferences. Rank-2 or rank-3 = multiple underlying preference axes. The only method that tells you *why* preferences cycle rather than just *that* they do. Requires ≥ 3×N comparisons for meaningful output. |

**Combinatorial / Voting Theory Models**

| Algorithm | Update | Description |
|---|---|---|
| **Schulze (Beatpath)** | Batch | If no Condorcet winner exists, finds the strongest-path winner: A beats B if the weakest link in chain A→…→B is stronger than any chain B→…→A. Handles cycles gracefully. Used in Debian and Wikimedia governance elections. |
| **Ranked Pairs (Tideman)** | Batch | Sort all pairwise victories by margin, lock them in strongest-first as long as no cycle is created. Similar results to Schulze via a different path. Marginally more intuitive to explain. |
| **Borda Count (derived)** | Batch | Score = win count. Trivially cheap. Derived from pairwise matrix rather than requiring full rank orderings as input. |

### 4.2 When Algorithms Disagree

The disagreement between algorithms is itself a signal:

| Divergence pattern | What it means |
|---|---|
| ELO and Bradley-Terry disagree | Sparse data — not enough comparisons yet |
| Score methods and Condorcet disagree | Cyclic preferences — genuine intransitivity |
| Glicko-2 / TrueSkill RD is wide | High uncertainty — item needs more comparisons |
| HodgeRank cyclic component is large | Preferences not well-modeled by any linear ranking |
| SerialRank second eigenvalue is small | Genuinely multidimensional preferences |
| Matrix factorization best rank ≥ 2 | Multiple independent preference axes exist |
| Borda and score methods disagree | Extreme rankings distorting results |

Consensus rank ± inter-algorithm variance is a more honest output than any single algorithm's point estimate.

### 4.3 Computation Tiers

| Tier | Algorithms | When computed |
|---|---|---|
| **Live** | ELO, Glicko-2 | After every comparison |
| **Results-time batch** | Bradley-Terry, TrueSkill, Thurstone, Borda, Copeland, Schulze, Ranked Pairs, PageRank, Markov, SpringRank | On demand at results screen |
| **Deep batch** | HodgeRank, SerialRank, Matrix Factorization | On demand; return null below minimum data threshold |

---

## 5. Core ELO Algorithm

### 5.1 Formula

```
E_A = 1 / (1 + 10^((R_B - R_A) / 400))
R_A' = R_A + K * (S_A - E_A)
```

- `R_A`, `R_B`: current ratings
- `E_A`: expected score for A (0.0–1.0)
- `S_A`: actual score — `1.0` win, `0.0` loss, `0.5` tie
- Starting rating: **1200**

### 5.2 K-Factor

| Item match count | K |
|---|---|
| < 10 | 64 |
| 10–29 | 32 |
| ≥ 30 | 16 |

Consumer apps may override the stage map via `EloConfig`.

### 5.3 Tie and Skip

- **Tie:** `S_A = S_B = 0.5`. Valid outcome.
- **Skip:** Ratings unchanged. Pair recorded as seen (suppressed from `nextMatch()` for recency window) but not counted toward `matchCount`. Skip-happy users don't inflate K-factor stage transitions.

---

## 6. Data Model

```dart
class EloItem {
  final String id;         // consumer-assigned, opaque to engine
  double rating;           // current ELO rating, starts at 1200
  int matchCount;          // comparisons completed (skips excluded)
  DateTime? lastSeen;
}

enum MatchOutcome { aWins, bWins, tie, skip }

class EloMatch {
  final String idA;
  final String idB;
  final MatchOutcome outcome;
  final DateTime timestamp;
}

enum SyncMode { standalone, asyncMerge, liveSession }

class EloSession {
  final String sessionId;
  final String? participantId;
  final SyncMode syncMode;
  final String? sessionCode;
  final String? hostParticipantId;
  final DateTime? expiresAt;
  final List<EloItem> items;
  final List<EloMatch> history;
}
```

---

## 7. API Surface

### 7.1 Core Engine

```dart
class EloEngine {
  EloEngine({
    required List<EloItem> items,
    List<EloMatch>? history,
    EloConfig? config,
  });

  /// Submit a match outcome. Updates live algorithms immediately.
  MatchResult record(String idA, String idB, MatchOutcome outcome);

  /// Suggest the next pair. Returns null when converged or all pairs exhausted.
  MatchProposal? nextMatch();

  /// True when rank order has stabilized (see §9).
  bool get isConverged;

  /// Current ranking by live algorithms (ELO + Glicko-2 consensus), highest first.
  List<EloItem> get rankings;

  /// Run full algorithm ensemble. Batch algorithms computed fresh on each call.
  RankingComparison compareAlgorithms();

  /// Pop the last recorded match and recalculate. Skips also undoable.
  void undo();

  Map<String, dynamic> toJson();

  static EloEngine fromJson(
    Map<String, dynamic> json, {
    bool skipReplay = false,
  });
}

class EloConfig {
  final int startingRating;
  final Map<int, int> kFactorStages;
  final int convergenceWindow;
  final double convergenceTau;
  final int minMatchesBeforeConverge;
  final bool allowTies;
  final Set<AlgorithmId> enabledAlgorithms;
}

class MatchResult {
  final EloItem itemA;
  final EloItem itemB;
  final double deltaA;
}

class MatchProposal {
  final EloItem itemA;
  final EloItem itemB;
  final double expectedA;   // E_A; how close to 50/50 this matchup is
}
```

### 7.2 Algorithm Ensemble Output

```dart
class RankingComparison {
  // Live
  final List<EloItem> eloRanking;
  final List<EloItem> glicko2Ranking;

  // Batch — null if insufficient data
  final List<EloItem>? bradleyTerryRanking;
  final List<EloItem>? trueskillRanking;
  final List<EloItem>? thurstonRanking;
  final List<EloItem>? springRankRanking;
  final List<EloItem>? pageRankRanking;
  final List<EloItem>? markovRanking;
  final List<EloItem>? copelandRanking;
  final List<EloItem>? schulzeRanking;
  final List<EloItem>? rankedPairsRanking;
  final List<EloItem>? bordaRanking;

  // Deep batch — null if < 3*N comparisons
  final HodgeResult? hodge;
  final SerialRankResult? serialRank;
  final MatrixFactorizationResult? matrixFactorization;

  /// Harmonic mean of rank positions across all non-null algorithms.
  final List<EloItem> consensusRanking;

  /// 1.0 = all algorithms agree perfectly.
  final double interAlgorithmKendallTau;

  /// Per-item rank spread across algorithms — where disagreement is largest.
  final List<AlgorithmDivergence> divergences;
}

class HodgeResult {
  final List<EloItem> gradientRanking;
  final List<CyclicCluster> cycles;
  final double cyclicMagnitude;    // 0.0 = perfectly transitive
  final double harmonicMagnitude;  // 0.0 = complete comparison data
}

class CyclicCluster {
  final List<EloItem> items;
  final double cycleStrength;
}

class SerialRankResult {
  final List<EloItem> ranking;
  final double rankability;   // second eigenvalue magnitude; 1.0 = perfectly rankable
}

class MatrixFactorizationResult {
  final int bestRank;
  final double explainedVariance;
  final List<PreferenceDimension> dimensions;
  final List<EloItem> consensusRanking;
}

class PreferenceDimension {
  final int dimensionIndex;
  final List<EloItem> highScorers;
  final List<EloItem> lowScorers;
}

class AlgorithmDivergence {
  final EloItem item;
  final Map<AlgorithmId, int> rankByAlgorithm;
  final int rankSpread;
}

enum AlgorithmId {
  elo, glicko2, bradleyTerry, trueskill, thurstone,
  springRank, pageRank, markov, copeland, schulze,
  rankedPairs, borda, hodge, serialRank, matrixFactorization,
}
```

### 7.3 Merge Utility

```dart
class EloMerge {
  /// Combine N independent sessions over the same item set.
  /// Partial sessions are valid input.
  static List<MergedResult> combine(
    List<EloSession> sessions, {
    MergeStrategy strategy = MergeStrategy.harmonicMean,
  });
}

class MergedResult {
  final EloItem item;
  final List<int> ranksByParticipant;
  final double combinedScore;
  final double agreement;   // 0.0–1.0
}

enum MergeStrategy { harmonicMean, arithmeticMean, minimum }
```

Harmonic mean is the correct default. If Partner A ranks "Eliot" #1 and Partner B ranks it #45, arithmetic mean scores it #23. Harmonic mean scores it near #38 — surfaces genuine overlap, not false consensus from one enthusiastic partner.

### 7.4 Sync (`sync.dart` — v2 only)

```dart
class EloSync {
  Future<void> push(EloSession session, SyncConfig config);
  Future<EloSession> pull(String sessionCode, String participantId, SyncConfig config);
  Stream<List<EloSession>> subscribe(String sessionCode, SyncConfig config);
  Future<List<String>> participants(String sessionCode);
}

class SyncConfig {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final Duration sessionTtl;
  final EncryptionKey encryptionKey;
}
```

Session blobs encrypted with XChaCha20-Poly1305 (reusing `sanctuary_auth` primitives) before push. Server stores opaque bytes only.

---

## 8. Pair Selection

**Priority score for candidate pair (A, B):**

```
priority = uncertainty(A) + uncertainty(B) + adjacency(A, B) - recency_penalty(A, B)

uncertainty(item) = 1.0 / (1 + item.matchCount)

adjacency(A, B)   = 1.0 - |E_A - 0.5| * 2
  // 1.0 at perfect 50/50, 0.0 when outcome is near-certain

recency_penalty   = 0.5 if seen within last min(10, N) matches, else 0.0
```

Adjacency weighting is the key insight: a comparison between items rated 1200 and 1500 tells you almost nothing. A comparison between items rated 1210 and 1220 is maximally informative.

O(N²) over candidate pairs. At N ≤ 500, well under 5ms on device.

---

## 9. Convergence Signal

After each match, recompute `rankings`. Compare rank order to 5 matches prior via Kendall's tau. If tau ≥ `convergenceTau` (default 0.95) for the last 5 intervals (25 consecutive matches), set `isConverged = true`.

Guard: never signal before `minMatchesBeforeConverge` (default `max(N, 20)`).

`isConverged` is advisory. Consumer apps decide what to do with it.

---

## 10. Serialization

```json
{
  "version": 1,
  "config": { "startingRating": 1200, "kFactorStages": {"0": 64, "10": 32, "30": 16} },
  "items": [
    { "id": "eliot", "rating": 1347.2, "matchCount": 18, "lastSeen": 1711000000 }
  ],
  "history": [
    { "idA": "eliot", "idB": "james", "outcome": "aWins", "ts": 1711000000 }
  ]
}
```

History is append-only. Ratings reconstructable from scratch by replaying history. `fromJson()` replays by default. `skipReplay: true` accepts stored ratings directly for history > ~500 matches.

---

## 11. v2 Sync Architecture

### Async Merge (Baby Names couples flow)

Partners rank independently, any time, no coordination required. One partner creates a session and shares a short alphanumeric `sessionCode`. The shared artifact is the item list. Rankings are private until merge is triggered.

Supabase schema:
- `sessions`: code, item list blob, host UUID, expires_at
- `participant_sessions`: session_code, participant_id, encrypted_ratings_blob, updated_at

### Live Session (Restaurant Chooser)

All participants vote simultaneously. Each participant's votes update their local session state. Group ranking computed by `EloMerge.combine()` on a 3-second debounce — not per vote. Voting is instant; leaderboard lags slightly. Correct tradeoff.

Supabase Realtime channel per session. TTL default 24 hours, consumer-configurable.

---

## 12. Testing Requirements

| Test | Pass Criteria |
|---|---|
| K-factor transitions | Correct K at match counts 9, 10, 29, 30 |
| ELO arithmetic | Output matches known tables to 4 decimal places |
| Convergence detection | 20-item synthetic dataset with known ground truth; converges to correct order within 3×N comparisons |
| Pair selection efficiency | 50-item session reaches tau ≥ 0.95 in ≥ 30% fewer matches than random selection |
| All batch algorithms | Output matches known results on reference datasets |
| HodgeRank decomposition | Cyclic component correctly identified on constructed cyclic preference data |
| SerialRank rankability | Returns low score on deliberately noisy/multidimensional preference data |
| Matrix factorization | Rank-2 solution correctly identified on two-axis synthetic preference data |
| Merge strategies | All three correct on known input; harmonic penalizes outlier ranks as specified |
| Round-trip serialization | `fromJson(toJson(engine))` produces identical rankings; replay and skipReplay both pass |
| Undo | Ratings return to pre-match state after pop |
| Skip handling | Skips don't increment `matchCount`; pair suppressed from `nextMatch()` for window |
| Edge cases | N=2, N=1, duplicate IDs (throw `ArgumentError`), empty history |
| Insufficient data guards | Deep batch algorithms return null below threshold |
| Sync round-trip (v2) | Push + pull yields byte-identical encrypted blob |

Target: 90%+ line coverage before Baby Names ships.

---

## 13. Open Questions

**Information-theoretic pair selection:** The current `nextMatch()` heuristic is good. A full information-theoretic selector (maximize expected information gain per comparison) would squeeze roughly 15–20% fewer comparisons to convergence but adds real complexity. Revisit if users report sessions feeling too long.

**Kemeny-Young:** Theoretically optimal ranking (minimizes total pairwise disagreements with observed data; maximum likelihood under Mallows model) is NP-hard to compute exactly for large N. An approximation is feasible. Omitted from v1 — the ensemble consensus already approximates it cheaply via harmonic mean of rank positions.

---

## 14. Delivery Checklist

**v1**
- [ ] Package scaffolded (`elo_engine`)
- [ ] Core data models
- [ ] `EloEngine` — record, nextMatch, rankings, isConverged, undo
- [ ] `EloConfig` — all overrides
- [ ] Live algorithms: ELO, Glicko-2
- [ ] Batch algorithms: Bradley-Terry, TrueSkill, Thurstone, SpringRank, PageRank, Markov, Copeland, Schulze, Ranked Pairs, Borda
- [ ] Deep batch algorithms: HodgeRank, SerialRank, Matrix Factorization
- [ ] `RankingComparison` ensemble output with consensus and divergence
- [ ] `EloMerge` — all three strategies
- [ ] JSON round-trip with replay + skipReplay
- [ ] Full test suite, 90%+ coverage
- [ ] Benchmarked: `nextMatch()` < 5ms at N=200; batch ensemble < 500ms at N=200
- [ ] Published to pub.dev under OpenHearth org

**v2**
- [ ] `SyncMode` + session metadata
- [ ] `EloSync` — async push/pull
- [ ] `EloSync` — live Realtime subscription
- [ ] Supabase schema
- [ ] Encryption via `sanctuary_auth`
- [ ] TTL-based session purge
- [ ] Integration tests: async merge round-trip, 3-participant live convergence

---

## Addendum — April 2026: Supabase Removed from Architecture

Supabase has been dropped from the OpenHearth architecture. The v2 sync section above references Supabase Realtime, Supabase schema, and `supabase_flutter` — these reflect a design that is no longer the plan.

**What this means for ELO Engine:**
- **v1 (pure Dart, no server):** Completely unaffected. Ship as designed.
- **v2 sync:** The `SyncBackend` interface concept is still valid, but the implementation will target a vendor-agnostic encrypted blob relay (Cloudflare R2 + Workers is the default candidate) rather than Supabase. Live Realtime sessions will use a purpose-built WebSocket relay or Cloudflare Durable Object, not Supabase Realtime.
- **`supabase_flutter` dependency:** Will not be added. v2 sync will use plain HTTPS for blob PUT/GET and WebSocket for live sessions.

See `OpenHearth/CLAUDE.md` (April 2026) for the current architecture.
