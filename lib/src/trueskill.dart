import 'dart:math';

/// Per-item TrueSkill state. Immutable; each update returns a new instance.
///
/// Uses the standard 1v1 Gaussian belief propagation update (Herbrich et al. 2007).
/// Parameters β = σ₀/2 (performance spread) are baked in as constants.
class TrueSkillState {
  /// Skill estimate. Initial value 25.0 for all new items.
  final double mu;

  /// Skill uncertainty. Lower = higher confidence. Initial value 25/3 ≈ 8.333.
  final double sigma;

  /// Constructs a state. Prefer [TrueSkillState.initial] for new items.
  const TrueSkillState({required this.mu, required this.sigma});

  /// Creates initial state for a new item. All items start at the same level
  /// (mu=25, sigma=25/3) on TrueSkill's own scale regardless of ELO config.
  factory TrueSkillState.initial() =>
      const TrueSkillState(mu: 25.0, sigma: 25.0 / 3.0);

  /// Conservative skill estimate (μ − 3σ): the lower-confidence-bound ranking
  /// value used in TrueSkill leaderboards. Converges toward μ as certainty grows.
  double get conservativeScore => mu - 3.0 * sigma;

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'mu': mu, 'sigma': sigma};

  /// Restores state from its [toJson] representation.
  factory TrueSkillState.fromJson(Map<String, dynamic> j) => TrueSkillState(
        mu: (j['mu'] as num).toDouble(),
        sigma: (j['sigma'] as num).toDouble(),
      );
}

// β: performance spread. Standard TrueSkill sets β = σ₀ / 2 = 25/6.
const _beta = 25.0 / 6.0;

/// Apply one TrueSkill 1v1 update for [state] vs [opponent].
///
/// [score] must be 1.0 (win), 0.5 (tie), or 0.0 (loss).
/// Tie is approximated as the average of the win and loss update directions,
/// preserving the correct qualitative behaviour (mu barely changes for equal
/// players; sigma decreases for both parties).
///
/// Returns the updated [TrueSkillState]; the original is unchanged.
TrueSkillState applyTrueSkill({
  required TrueSkillState state,
  required TrueSkillState opponent,
  required double score,
}) {
  assert(score == 0.0 || score == 0.5 || score == 1.0,
      'score must be 0.0, 0.5, or 1.0');

  final c2 = state.sigma * state.sigma +
      opponent.sigma * opponent.sigma +
      2.0 * _beta * _beta;
  final c = sqrt(c2);
  final t = (state.mu - opponent.mu) / c;
  final sigSq = state.sigma * state.sigma;

  if (score == 1.0) {
    final v = _vWin(t);
    final w = v * (v + t);
    return TrueSkillState(
      mu: state.mu + sigSq / c * v,
      sigma: state.sigma * sqrt((1.0 - sigSq / c2 * w).clamp(0.0, 1.0)),
    );
  } else if (score == 0.0) {
    final v = _vWin(-t);
    final w = v * (v - t);
    return TrueSkillState(
      mu: state.mu - sigSq / c * v,
      sigma: state.sigma * sqrt((1.0 - sigSq / c2 * w).clamp(0.0, 1.0)),
    );
  } else {
    // score == 0.5: tie — average of win and loss update directions.
    final vW = _vWin(t);
    final wW = vW * (vW + t);
    final vL = _vWin(-t);
    final wL = vL * (vL - t);
    final muDelta = sigSq / c * (vW - vL) / 2.0;
    final wAvg = (wW + wL) / 2.0;
    return TrueSkillState(
      mu: state.mu + muDelta,
      sigma: state.sigma * sqrt((1.0 - sigSq / c2 * wAvg).clamp(0.0, 1.0)),
    );
  }
}

// V(t) = φ(t) / Φ(t) — the truncated normal factor (Mills ratio).
// Guard: when Φ(t) → 0 (extreme t), approximate V(t) ≈ |t| (large-t behaviour).
double _vWin(double t) {
  final phiT = _phi(t);
  final PhiT = _normalCdf(t);
  return PhiT < 1e-10 ? t.abs() : phiT / PhiT;
}

// Standard normal PDF: φ(x) = exp(−x²/2) / √(2π)
double _phi(double x) => exp(-0.5 * x * x) / sqrt(2.0 * pi);

// Normal CDF Φ(x) via Abramowitz & Stegun 26.2.17 rational approximation.
// Max |error| < 7.5×10⁻⁸ for all x. Clipped to exact 0/1 beyond ±8.
double _normalCdf(double x) {
  if (x < -8.0) return 0.0;
  if (x > 8.0) return 1.0;
  const a = [0.319381530, -0.356563782, 1.781477937, -1.821255978, 1.330274429];
  final k = 1.0 / (1.0 + 0.2316419 * x.abs());
  var poly = 0.0;
  var kPow = k;
  for (final ai in a) {
    poly += ai * kPow;
    kPow *= k;
  }
  final result = 1.0 - _phi(x) * poly;
  return x >= 0 ? result : 1.0 - result;
}
