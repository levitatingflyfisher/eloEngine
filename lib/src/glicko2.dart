import 'dart:math';

/// Per-item Glicko-2 state. Immutable; each update returns a new instance.
class Glicko2State {
  /// Internal-scale rating: μ = (displayRating − 1500) / 173.7178.
  final double mu;

  /// Internal-scale rating deviation: φ = displayRd / 173.7178.
  final double phi;

  /// Volatility (σ): measures consistency of performance. Typical range 0.3–1.2%.
  final double sigma;

  /// Constructs a state from raw internal-scale parameters. Prefer
  /// [Glicko2State.initial] for new items.
  const Glicko2State({
    required this.mu,
    required this.phi,
    required this.sigma,
  });

  /// Creates initial state for a new item. Uses Glickman's recommended defaults:
  /// RD = 350 (maximum uncertainty). [startingRating] is the display-scale rating.
  factory Glicko2State.initial({int startingRating = 1200}) => Glicko2State(
        mu: (startingRating - 1500.0) / 173.7178,
        phi: 350.0 / 173.7178,
        sigma: 0.06,
      );

  /// Display-scale rating (the number consumers typically care about).
  double get displayRating => 173.7178 * mu + 1500.0;

  /// Display-scale rating deviation.
  double get displayRd => 173.7178 * phi;

  /// Serializes to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'mu': mu, 'phi': phi, 'sigma': sigma};

  /// Restores state from its [toJson] representation.
  factory Glicko2State.fromJson(Map<String, dynamic> j) => Glicko2State(
        mu: (j['mu'] as num).toDouble(),
        phi: (j['phi'] as num).toDouble(),
        sigma: (j['sigma'] as num).toDouble(),
      );
}

// Internal: g(φ) scaling factor (Glickman 2012 §3 Step 1).
double _g(double phi) => 1.0 / sqrt(1.0 + 3.0 * phi * phi / (pi * pi));

/// Expected score for item with internal rating [mu] against opponent with
/// internal rating [muJ] and internal RD [phiJ] (Glickman 2012 §3 Step 2).
double glicko2ExpectedScore(double mu, double muJ, double phiJ) =>
    1.0 / (1.0 + exp(-_g(phiJ) * (mu - muJ)));

// Illinois algorithm for volatility update (Glickman 2012 §3 Step 5).
double _newSigma({
  required double sigma,
  required double phi,
  required double v,
  required double delta,
  required double tau,
}) {
  final a = log(sigma * sigma);
  final deltaSquared = delta * delta;
  final phiSquared = phi * phi;
  final tauSquared = tau * tau;

  double f(double x) {
    final ex = exp(x);
    final denom = phiSquared + v + ex;
    return (ex * (deltaSquared - phiSquared - v - ex)) / (2.0 * denom * denom) -
        (x - a) / tauSquared;
  }

  double bigA = a;
  double bigB;
  if (deltaSquared > phiSquared + v) {
    bigB = log(deltaSquared - phiSquared - v);
  } else {
    var k = 1;
    while (f(a - k * tau) < 0 && k < 1000) {
      k++;
    }
    bigB = a - k * tau;
  }

  var fA = f(bigA);
  var fB = f(bigB);

  for (var i = 0; i < 100 && (bigB - bigA).abs() > 1e-6; i++) {
    final c = bigA + (bigA - bigB) * fA / (fB - fA);
    final fC = f(c);
    if (fC * fB < 0) {
      bigA = bigB;
      fA = fB;
    } else {
      fA /= 2.0;
    }
    bigB = c;
    fB = fC;
  }

  return exp(bigA / 2.0);
}

/// Apply one Glicko-2 comparison update for [state] vs [opponent].
///
/// [score] is 1.0 (win), 0.5 (tie), or 0.0 (loss).
/// [tau] is the system constant controlling how quickly volatility changes
/// (Glickman recommends 0.3–1.2; default 0.5 matches his worked example).
///
/// Returns the updated [Glicko2State]; the original is unchanged.
Glicko2State applyGlicko2({
  required Glicko2State state,
  required Glicko2State opponent,
  required double score,
  double tau = 0.5,
}) {
  assert(score >= 0.0 && score <= 1.0, 'score must be in [0.0, 1.0]');
  final g = _g(opponent.phi);
  final e = glicko2ExpectedScore(state.mu, opponent.mu, opponent.phi);
  final v = 1.0 / (g * g * e * (1.0 - e));
  // Degenerate case: extreme rating gap causes e → 0 or e → 1; skip update.
  if (!v.isFinite) return state;
  final delta = v * g * (score - e);

  final newSigma = _newSigma(
    sigma: state.sigma,
    phi: state.phi,
    v: v,
    delta: delta,
    tau: tau,
  );
  final phiStar = sqrt(state.phi * state.phi + newSigma * newSigma);
  final newPhi = 1.0 / sqrt(1.0 / (phiStar * phiStar) + 1.0 / v);
  final newMu = state.mu + newPhi * newPhi * g * (score - e);

  return Glicko2State(mu: newMu, phi: newPhi, sigma: newSigma);
}
