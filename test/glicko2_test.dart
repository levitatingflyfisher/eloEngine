import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';

void main() {
  group('Glicko2State', () {
    test('initial displayRating equals startingRating', () {
      final s = Glicko2State.initial(startingRating: 1200);
      expect(s.displayRating, closeTo(1200.0, 0.01));
    });

    test('initial displayRd is 350', () {
      final s = Glicko2State.initial(startingRating: 1200);
      expect(s.displayRd, closeTo(350.0, 0.01));
    });

    test('JSON round-trip preserves all fields', () {
      final s = Glicko2State(mu: 0.42, phi: 1.23, sigma: 0.055);
      final s2 = Glicko2State.fromJson(s.toJson());
      expect(s2.mu, closeTo(s.mu, 1e-9));
      expect(s2.phi, closeTo(s.phi, 1e-9));
      expect(s2.sigma, closeTo(s.sigma, 1e-9));
    });
  });

  group('glicko2ExpectedScore', () {
    test('equal ratings → 0.5', () {
      final s = Glicko2State.initial(startingRating: 1200);
      expect(glicko2ExpectedScore(s.mu, s.mu, s.phi), closeTo(0.5, 0.001));
    });
  });

  group('applyGlicko2', () {
    test('winner displayRating increases', () {
      final a = Glicko2State.initial(startingRating: 1200);
      final updated = applyGlicko2(state: a, opponent: a, score: 1.0);
      expect(updated.displayRating, greaterThan(1200.0));
    });

    test('loser displayRating decreases', () {
      final a = Glicko2State.initial(startingRating: 1200);
      final updated = applyGlicko2(state: a, opponent: a, score: 0.0);
      expect(updated.displayRating, lessThan(1200.0));
    });

    test('displayRd decreases after a match (RD shrinks as certainty grows)', () {
      final a = Glicko2State.initial(startingRating: 1200);
      final updated = applyGlicko2(state: a, opponent: a, score: 1.0);
      expect(updated.displayRd, lessThan(350.0));
    });

    test('reference: single win vs weaker opponent', () {
      // Glickman (2012) §3 player setup: r=1500, RD=200, σ=0.06 beats opponent
      // at r=1400, RD=30 in a single-game rating period.
      // Single-game intermediate values (§3 Step 1–4): g≈0.9955, E≈0.6395,
      // v≈4.377, Δ≈1.571. After Illinois volatility update and φ' calculation:
      // r' ≈ 1563.6, RD' ≈ 175.4.
      // (The paper's §3 final results of r'=1464, RD'=151 are for a 3-game period.)
      final player = Glicko2State(
        mu: 0.0,
        phi: 200.0 / 173.7178,
        sigma: 0.06,
      );
      final opponent = Glicko2State(
        mu: (1400.0 - 1500.0) / 173.7178,
        phi: 30.0 / 173.7178,
        sigma: 0.06,
      );
      final updated = applyGlicko2(state: player, opponent: opponent, score: 1.0);
      expect(updated.displayRating, closeTo(1563.6, 0.5));
      expect(updated.displayRd, closeTo(175.4, 0.5));
    });

    test('tie between equal-rated players leaves mu unchanged', () {
      final a = Glicko2State.initial(startingRating: 1200);
      final updated = applyGlicko2(state: a, opponent: a, score: 0.5);
      // score - E = 0.5 - 0.5 = 0 → no mu change
      expect(updated.displayRating, closeTo(1200.0, 0.01));
      // RD still decreases (we gained information)
      expect(updated.displayRd, lessThan(350.0));
    });
  });
}
