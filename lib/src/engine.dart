import 'dart:math';
import 'models.dart';
import 'elo_math.dart';
import 'glicko2.dart';
import 'trueskill.dart';
import 'batch_algorithms.dart';
import 'parametric_algorithms.dart';
import 'pairwise_matrix.dart';
import 'ranking_comparison.dart';
import 'session.dart';

/// Pairwise comparison ranking engine using ELO ratings.
///
/// Holds mutable [EloItem] instances — [MatchResult] and [MatchProposal]
/// return live references that reflect subsequent matches.
/// Not thread-safe. Undo replays full history: O(history × items).
class EloEngine {
  final Map<String, EloItem> _items;
  final List<EloMatch> _history;
  final EloConfig _config;

  late Map<String, Glicko2State> _glicko2States;
  late Map<String, TrueSkillState> _trueSkillStates;

  // Convergence tracking
  final List<List<String>> _rankSnapshots = [];
  final List<double> _tauHistory = [];
  bool _isConverged = false;
  int _totalNonSkipMatches = 0;

  /// Constructs an engine over [items]. If [history] is supplied, each match
  /// is replayed against fresh algorithm state (this is how you restore
  /// from JSON). [config] defaults to `const EloConfig()`.
  ///
  /// Throws [ArgumentError] if items have duplicate IDs or if
  /// [EloConfig.enabledAlgorithms] is an empty set.
  EloEngine({
    required List<EloItem> items,
    List<EloMatch>? history,
    EloConfig? config,
  })  : _items = {for (final i in items) i.id: i},
        _history = [],
        _config = config ?? const EloConfig() {
    if (_items.length != items.length) {
      throw ArgumentError('Duplicate item IDs detected');
    }
    if (_config.enabledAlgorithms != null &&
        _config.enabledAlgorithms!.isEmpty) {
      throw ArgumentError(
          'EloConfig.enabledAlgorithms must be null or non-empty');
    }
    _glicko2States = _isEnabled(AlgorithmId.glicko2)
        ? {
            for (final id in _items.keys)
              id: Glicko2State.initial(startingRating: _config.startingRating)
          }
        : <String, Glicko2State>{};
    _trueSkillStates = _isEnabled(AlgorithmId.trueskill)
        ? {for (final id in _items.keys) id: TrueSkillState.initial()}
        : <String, TrueSkillState>{};
    if (history != null) {
      for (final match in history) {
        _history.add(match);
        _applyMatchState(match);
      }
    }
  }

  bool _isEnabled(AlgorithmId id) =>
      _config.enabledAlgorithms == null ||
      _config.enabledAlgorithms!.contains(id);

  /// Current ranking, highest rated first.
  List<EloItem> get rankings {
    final sorted = _items.values.toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return sorted;
  }

  /// All items in their original insertion order, regardless of rating.
  List<EloItem> get items => _items.values.toList();

  /// Read-only view of recorded match history (insertion order).
  List<EloMatch> get history => List.unmodifiable(_history);

  /// Whether the engine has detected a stable ranking. See
  /// [EloConfig.convergenceWindow], [EloConfig.convergenceTau], and
  /// [EloConfig.minMatchesBeforeConverge] for the exact criteria.
  bool get isConverged => _isConverged;

  /// Snapshot the engine state into an [EloSession] for merging or persistence.
  ///
  /// The returned session contains live references to the engine's [EloItem]
  /// instances — subsequent matches will mutate them. Pair this with
  /// [EloMerge.combine] when one device hosts multiple participants who each
  /// build their own ranking.
  EloSession snapshot({String? participantId}) => EloSession(
        participantId: participantId,
        items: _items.values.toList(),
        history: List.of(_history),
      );

  /// Record a match outcome. Updates ELO immediately.
  ///
  /// Throws [ArgumentError] if [idA] or [idB] is unknown, or if
  /// [outcome] is [MatchOutcome.tie] while [EloConfig.allowTies] is false.
  MatchResult record(String idA, String idB, MatchOutcome outcome) {
    if (!_items.containsKey(idA)) throw ArgumentError('Unknown id: $idA');
    if (!_items.containsKey(idB)) throw ArgumentError('Unknown id: $idB');
    if (outcome == MatchOutcome.tie && !_config.allowTies) {
      throw ArgumentError(
          'Ties are disabled by EloConfig.allowTies; pick a winner');
    }
    final match = EloMatch(
        idA: idA, idB: idB, outcome: outcome, timestamp: DateTime.now());
    _history.add(match);
    return _applyMatchState(match);
  }

  MatchResult _applyMatchState(EloMatch match) {
    final itemA = _items[match.idA]!;
    final itemB = _items[match.idB]!;

    if (match.outcome == MatchOutcome.skip) {
      return MatchResult(itemA: itemA, itemB: itemB, deltaA: 0.0);
    }

    final scoreA = switch (match.outcome) {
      MatchOutcome.aWins => 1.0,
      MatchOutcome.bWins => 0.0,
      MatchOutcome.tie => 0.5,
      MatchOutcome.skip => throw StateError('unreachable'),
    };

    final update = applyElo(
      ratingA: itemA.rating,
      ratingB: itemB.rating,
      matchCountA: itemA.matchCount,
      matchCountB: itemB.matchCount,
      scoreA: scoreA,
      kFactorStages: _config.kFactorStages,
    );

    itemA.rating = update.ratingA;
    itemA.matchCount++;
    itemA.lastSeen = match.timestamp;

    itemB.rating = update.ratingB;
    itemB.matchCount++;
    itemB.lastSeen = match.timestamp;

    // Glicko-2 update (online: one match per rating period). Gated on config.
    if (_isEnabled(AlgorithmId.glicko2)) {
      final stateA = _glicko2States[match.idA]!;
      final stateB = _glicko2States[match.idB]!;
      _glicko2States[match.idA] =
          applyGlicko2(state: stateA, opponent: stateB, score: scoreA);
      _glicko2States[match.idB] =
          applyGlicko2(state: stateB, opponent: stateA, score: 1.0 - scoreA);
    }

    // TrueSkill update (online: Gaussian belief propagation). Gated on config.
    if (_isEnabled(AlgorithmId.trueskill)) {
      final tsA = _trueSkillStates[match.idA]!;
      final tsB = _trueSkillStates[match.idB]!;
      _trueSkillStates[match.idA] =
          applyTrueSkill(state: tsA, opponent: tsB, score: scoreA);
      _trueSkillStates[match.idB] =
          applyTrueSkill(state: tsB, opponent: tsA, score: 1.0 - scoreA);
    }

    _totalNonSkipMatches++;
    _updateConvergence();

    return MatchResult(itemA: itemA, itemB: itemB, deltaA: update.deltaA);
  }

  void _updateConvergence() {
    final currentOrder = rankings.map((i) => i.id).toList();
    _rankSnapshots.add(currentOrder);

    final windowBack = _config.convergenceWindow; // compare current rank to rank `windowBack` matches ago
    if (_rankSnapshots.length > windowBack) {
      final tau = kendallTau(
        currentOrder,
        _rankSnapshots[_rankSnapshots.length - 1 - windowBack],
      );
      _tauHistory.add(tau);
    }

    final n = _items.length;
    final minMatches = _config.minMatchesBeforeConverge > 0
        ? _config.minMatchesBeforeConverge
        : max(n, 20);

    if (_totalNonSkipMatches >= minMatches && _tauHistory.length >= 5) {
      final lastFive = _tauHistory.sublist(_tauHistory.length - 5);
      _isConverged = lastFive.every((t) => t >= _config.convergenceTau);
    }
  }

  /// Suggest the next pair to compare. Returns null when converged or N < 2.
  MatchProposal? nextMatch() {
    final itemsList = _items.values.toList();
    final n = itemsList.length;
    if (n < 2 || _isConverged) return null;

    // Skipped pairs also enter the recency window — intentional: don't re-propose
    // a pair immediately after the user skipped it (treat skip as "not now").
    final windowSize = min(10, n);
    final recentPairs = <String>{};
    for (var i = _history.length - 1;
        i >= 0 && (_history.length - 1 - i) < windowSize;
        i--) {
      recentPairs.add(_pairKey(_history[i].idA, _history[i].idB));
    }

    var bestPriority = double.negativeInfinity;
    EloItem? bestA, bestB;

    for (var i = 0; i < n - 1; i++) {
      for (var j = i + 1; j < n; j++) {
        final a = itemsList[i];
        final b = itemsList[j];
        final eA = expectedScore(a.rating, b.rating);
        final uncertainty =
            1.0 / (1 + a.matchCount) + 1.0 / (1 + b.matchCount);
        final adjacency = 1.0 - (eA - 0.5).abs() * 2;
        final recencyPenalty =
            recentPairs.contains(_pairKey(a.id, b.id)) ? 0.5 : 0.0;
        final priority = uncertainty + adjacency - recencyPenalty;

        if (priority > bestPriority) {
          bestPriority = priority;
          bestA = a;
          bestB = b;
        }
      }
    }

    if (bestA == null) return null;
    return MatchProposal(
      itemA: bestA,
      itemB: bestB!,
      expectedA: expectedScore(bestA.rating, bestB.rating),
    );
  }

  String _pairKey(String idA, String idB) =>
      idA.compareTo(idB) <= 0 ? '$idA|$idB' : '$idB|$idA';

  /// Items sorted by Glicko-2 display rating, highest first.
  List<EloItem> _glicko2Ranking() {
    final sorted = _items.values.toList()
      ..sort((a, b) =>
          _glicko2States[b.id]!.displayRating
              .compareTo(_glicko2States[a.id]!.displayRating));
    return sorted;
  }

  /// Items sorted by TrueSkill conservative score (μ − 3σ), highest first.
  List<EloItem> _trueSkillRanking() {
    final sorted = _items.values.toList()
      ..sort((a, b) => _trueSkillStates[b.id]!.conservativeScore
          .compareTo(_trueSkillStates[a.id]!.conservativeScore));
    return sorted;
  }

  /// Convert a ranked list of item IDs to the corresponding EloItem list.
  List<EloItem> _idsToItems(List<String> ids) =>
      ids.map((id) => _items[id]!).toList();

  /// Consensus ranking: items sorted by harmonic mean of rank-scores across
  /// all provided [activeRankings]. rank-score = (N − rank_position).
  List<EloItem> _consensusRanking(List<List<EloItem>> activeRankings) {
    if (activeRankings.isEmpty) return _items.values.toList();
    final n = _items.length;
    // Accumulate sum of (1/score) for each item. Lower sum = higher harmonic mean = better.
    final sumReciprocal = <String, double>{};
    for (final id in _items.keys) {
      sumReciprocal[id] = 0.0;
    }
    for (final ranking in activeRankings) {
      for (var i = 0; i < ranking.length; i++) {
        final score = (n - i).toDouble();
        sumReciprocal[ranking[i].id] =
            sumReciprocal[ranking[i].id]! + 1.0 / score;
      }
    }
    return _items.values.toList()
      ..sort((a, b) =>
          sumReciprocal[a.id]!.compareTo(sumReciprocal[b.id]!));
  }

  /// Average pairwise Kendall's tau across all non-null rankings.
  double _interAlgorithmTau(List<List<EloItem>> activeRankings) {
    if (activeRankings.length < 2) return 1.0;
    var total = 0.0;
    var count = 0;
    for (var i = 0; i < activeRankings.length - 1; i++) {
      for (var j = i + 1; j < activeRankings.length; j++) {
        total += kendallTau(
          activeRankings[i].map((e) => e.id).toList(),
          activeRankings[j].map((e) => e.id).toList(),
        );
        count++;
      }
    }
    return count == 0 ? 1.0 : total / count;
  }

  /// Per-item rank spread across all non-null rankings.
  List<AlgorithmDivergence> _divergences(
      Map<AlgorithmId, List<EloItem>> rankingMap) {
    return _items.values.map((item) {
      final rankByAlgorithm = <AlgorithmId, int>{};
      for (final entry in rankingMap.entries) {
        final rank = entry.value.indexWhere((e) => e.id == item.id);
        if (rank >= 0) rankByAlgorithm[entry.key] = rank;
      }
      final ranks = rankByAlgorithm.values.toList();
      final spread = ranks.isEmpty ? 0 : ranks.reduce(max) - ranks.reduce(min);
      return AlgorithmDivergence(
        item: item,
        rankByAlgorithm: rankByAlgorithm,
        rankSpread: spread,
      );
    }).toList();
  }

  /// Run the algorithm ensemble. By default all 15 algorithms run; restrict
  /// via [EloConfig.enabledAlgorithms]. Disabled algorithms appear as `null`
  /// in the returned [RankingComparison] and are excluded from
  /// `consensusRanking`, `interAlgorithmKendallTau`, and `divergences`.
  RankingComparison compareAlgorithms() {
    final ids = _items.keys.toList();
    // Only build the pairwise matrix if at least one batch algorithm is
    // enabled — it's O(history) and pointless otherwise.
    final needsMatrix = _anyBatchEnabled();
    final matrix =
        needsMatrix ? PairwiseMatrix.fromHistory(ids, _history) : null;

    final eloOrder = _isEnabled(AlgorithmId.elo) ? rankings : null;
    final g2Order =
        _isEnabled(AlgorithmId.glicko2) ? _glicko2Ranking() : null;
    final tsOrder =
        _isEnabled(AlgorithmId.trueskill) ? _trueSkillRanking() : null;
    final bordaOrder = _isEnabled(AlgorithmId.borda)
        ? _idsToItems(bordaRanking(matrix!))
        : null;
    final copelandOrder = _isEnabled(AlgorithmId.copeland)
        ? _idsToItems(copelandRanking(matrix!))
        : null;
    final pageRankOrder = _isEnabled(AlgorithmId.pageRank)
        ? _idsToItems(pageRankRanking(matrix!))
        : null;
    final markovOrder = _isEnabled(AlgorithmId.markov)
        ? _idsToItems(markovRanking(matrix!))
        : null;
    final schulzeOrder = _isEnabled(AlgorithmId.schulze)
        ? _idsToItems(schulzeRanking(matrix!))
        : null;
    final rankedPairsOrder = _isEnabled(AlgorithmId.rankedPairs)
        ? _idsToItems(rankedPairsRanking(matrix!))
        : null;
    final btOrder = _isEnabled(AlgorithmId.bradleyTerry)
        ? _idsToItems(bradleyTerryRanking(matrix!))
        : null;
    final thurstoneOrder = _isEnabled(AlgorithmId.thurstone)
        ? _idsToItems(thurstoneRanking(matrix!))
        : null;
    final springOrder = _isEnabled(AlgorithmId.springRank)
        ? _idsToItems(springRankRanking(matrix!))
        : null;

    HodgeResult? hodgeResult;
    if (_isEnabled(AlgorithmId.hodge)) {
      final r = hodgeRanking(matrix!);
      hodgeResult = HodgeResult(
        gradientRanking: _idsToItems(r.ranking),
        cyclicMagnitude: r.cyclicMagnitude,
        harmonicMagnitude: r.harmonicMagnitude,
      );
    }

    SerialRankResult? serialResult;
    if (_isEnabled(AlgorithmId.serialRank)) {
      final r = serialRanking(matrix!);
      serialResult = SerialRankResult(
        ranking: _idsToItems(r.ranking),
        rankability: r.rankability,
      );
    }

    MatrixFactorizationResult? mfResult;
    if (_isEnabled(AlgorithmId.matrixFactorization)) {
      final r = matrixFactorizationRanking(matrix!);
      mfResult = MatrixFactorizationResult(
        bestRank: r.bestRank,
        explainedVariance: r.explainedVariance,
        consensusRanking: _idsToItems(r.ranking),
      );
    }

    // Build the rankingMap out of only the algorithms that ran. Ensemble
    // synthesis (consensus, tau, divergences) aggregates over this map
    // only — disabled algorithms have zero influence.
    final rankingMap = <AlgorithmId, List<EloItem>>{
      if (eloOrder != null) AlgorithmId.elo: eloOrder,
      if (g2Order != null) AlgorithmId.glicko2: g2Order,
      if (tsOrder != null) AlgorithmId.trueskill: tsOrder,
      if (bordaOrder != null) AlgorithmId.borda: bordaOrder,
      if (copelandOrder != null) AlgorithmId.copeland: copelandOrder,
      if (pageRankOrder != null) AlgorithmId.pageRank: pageRankOrder,
      if (markovOrder != null) AlgorithmId.markov: markovOrder,
      if (schulzeOrder != null) AlgorithmId.schulze: schulzeOrder,
      if (rankedPairsOrder != null)
        AlgorithmId.rankedPairs: rankedPairsOrder,
      if (btOrder != null) AlgorithmId.bradleyTerry: btOrder,
      if (thurstoneOrder != null) AlgorithmId.thurstone: thurstoneOrder,
      if (springOrder != null) AlgorithmId.springRank: springOrder,
      if (hodgeResult != null)
        AlgorithmId.hodge: hodgeResult.gradientRanking,
      if (serialResult != null)
        AlgorithmId.serialRank: serialResult.ranking,
      if (mfResult != null)
        AlgorithmId.matrixFactorization: mfResult.consensusRanking,
    };
    final activeRankings = rankingMap.values.toList();

    return RankingComparison(
      eloRanking: eloOrder,
      glicko2Ranking: g2Order,
      trueskillRanking: tsOrder,
      bordaRanking: bordaOrder,
      copelandRanking: copelandOrder,
      pageRankRanking: pageRankOrder,
      markovRanking: markovOrder,
      schulzeRanking: schulzeOrder,
      rankedPairsRanking: rankedPairsOrder,
      bradleyTerryRanking: btOrder,
      thurstoneRanking: thurstoneOrder,
      springRankRanking: springOrder,
      hodge: hodgeResult,
      serialRank: serialResult,
      matrixFactorization: mfResult,
      consensusRanking: _consensusRanking(activeRankings),
      interAlgorithmKendallTau: _interAlgorithmTau(activeRankings),
      divergences: _divergences(rankingMap),
    );
  }

  /// True if any algorithm that needs a [PairwiseMatrix] is enabled.
  bool _anyBatchEnabled() {
    const batchIds = {
      AlgorithmId.borda,
      AlgorithmId.copeland,
      AlgorithmId.pageRank,
      AlgorithmId.markov,
      AlgorithmId.schulze,
      AlgorithmId.rankedPairs,
      AlgorithmId.bradleyTerry,
      AlgorithmId.thurstone,
      AlgorithmId.springRank,
      AlgorithmId.hodge,
      AlgorithmId.serialRank,
      AlgorithmId.matrixFactorization,
    };
    if (_config.enabledAlgorithms == null) return true;
    return _config.enabledAlgorithms!.any(batchIds.contains);
  }

  /// Pop the last match and recalculate all state from history.
  void undo() {
    if (_history.isEmpty) return;
    _history.removeLast();
    _resetAndReplay();
  }

  void _resetAndReplay() {
    for (final item in _items.values) {
      item.rating = _config.startingRating.toDouble();
      item.matchCount = 0;
      item.lastSeen = null;
    }
    _rankSnapshots.clear();
    _tauHistory.clear();
    _isConverged = false;
    _totalNonSkipMatches = 0;
    _glicko2States = _isEnabled(AlgorithmId.glicko2)
        ? {
            for (final id in _items.keys)
              id: Glicko2State.initial(startingRating: _config.startingRating)
          }
        : <String, Glicko2State>{};
    _trueSkillStates = _isEnabled(AlgorithmId.trueskill)
        ? {for (final id in _items.keys) id: TrueSkillState.initial()}
        : <String, TrueSkillState>{};

    for (final match in _history) {
      _applyMatchState(match);
    }
  }

  /// Serializes the full engine state (config, items, history, convergence,
  /// Glicko-2 and TrueSkill states) to a JSON-compatible map. Round-trips
  /// via [EloEngine.fromJson].
  Map<String, dynamic> toJson() => {
        'version': 1,
        'config': _config.toJson(),
        'items': _items.values.map((i) => i.toJson()).toList(),
        'history': _history.map((m) => m.toJson()).toList(),
        'isConverged': _isConverged,
        'glicko2': _glicko2States.map((id, s) => MapEntry(id, s.toJson())),
        'trueskill': _trueSkillStates.map((id, s) => MapEntry(id, s.toJson())),
      };

  /// Restores an engine from its [toJson] representation.
  ///
  /// By default, match history is replayed against fresh algorithm state so
  /// Glicko-2/TrueSkill rebuild correctly. Pass `skipReplay: true` to accept
  /// the stored ELO ratings as-is — useful for histories longer than ~500
  /// matches where replay is a noticeable wait. Note that `skipReplay`
  /// cannot rebuild Glicko-2 or TrueSkill state; they are restored from the
  /// serialized `glicko2`/`trueskill` maps instead.
  static EloEngine fromJson(Map<String, dynamic> json,
      {bool skipReplay = false}) {
    final config =
        EloConfig.fromJson(json['config'] as Map<String, dynamic>? ?? {});
    final history = (json['history'] as List<dynamic>)
        .map((j) => EloMatch.fromJson(j as Map<String, dynamic>))
        .toList();

    if (skipReplay) {
      // Accept stored ratings directly (useful for history > ~500 matches).
      final items = (json['items'] as List<dynamic>)
          .map((j) => EloItem.fromJson(j as Map<String, dynamic>))
          .toList();
      final engine = EloEngine(items: items, config: config);
      engine._history.addAll(history);
      engine._totalNonSkipMatches =
          history.where((m) => m.outcome != MatchOutcome.skip).length;
      engine._isConverged = json['isConverged'] as bool? ?? false;
      // Restore Glicko-2 states only if all item IDs are present in the stored
      // snapshot. If any are missing (older engine format), leave all at initial
      // states — a partial restore would produce a silently incorrect Glicko-2 ranking.
      final g2Json = json['glicko2'] as Map<String, dynamic>?;
      if (g2Json != null) {
        final allPresent =
            engine._glicko2States.keys.every((id) => g2Json.containsKey(id));
        if (allPresent) {
          for (final entry in g2Json.entries) {
            engine._glicko2States[entry.key] =
                Glicko2State.fromJson(entry.value as Map<String, dynamic>);
          }
        }
      }
      // Restore TrueSkill states only if all item IDs are present.
      final tsJson = json['trueskill'] as Map<String, dynamic>?;
      if (tsJson != null) {
        final allTsPresent =
            engine._trueSkillStates.keys.every((id) => tsJson.containsKey(id));
        if (allTsPresent) {
          for (final entry in tsJson.entries) {
            engine._trueSkillStates[entry.key] =
                TrueSkillState.fromJson(entry.value as Map<String, dynamic>);
          }
        }
      }
      return engine;
    }

    // Default: replay from scratch (stored ratings ignored).
    final items = (json['items'] as List<dynamic>)
        .map((j) =>
            EloItem(id: (j as Map<String, dynamic>)['id'] as String))
        .toList();
    return EloEngine(items: items, history: history, config: config);
  }
}
