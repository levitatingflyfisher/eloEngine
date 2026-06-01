import 'package:test/test.dart';
import 'package:elo_engine/elo_engine.dart';

void main() {
  group('TrueSkillState', () {
    test('initial mu is 25.0', () {
      expect(TrueSkillState.initial().mu, 25.0);
    });

    test('initial sigma is 25/3', () {
      expect(TrueSkillState.initial().sigma, closeTo(25.0 / 3.0, 0.0001));
    });

    test('conservativeScore is mu − 3·sigma (= 0 at initial)', () {
      final s = TrueSkillState.initial();
      expect(s.conservativeScore, closeTo(s.mu - 3.0 * s.sigma, 0.0001));
      expect(s.conservativeScore, closeTo(0.0, 0.0001));
    });

    test('JSON round-trip preserves mu and sigma', () {
      final s = TrueSkillState(mu: 28.5, sigma: 6.3);
      final rt = TrueSkillState.fromJson(s.toJson());
      expect(rt.mu, closeTo(28.5, 0.0001));
      expect(rt.sigma, closeTo(6.3, 0.0001));
    });
  });

  group('applyTrueSkill', () {
    test('winner mu increases after win against equal opponent', () {
      final a = TrueSkillState.initial();
      final updated = applyTrueSkill(state: a, opponent: a, score: 1.0);
      expect(updated.mu, greaterThan(25.0));
    });

    test('loser mu decreases after loss against equal opponent', () {
      final a = TrueSkillState.initial();
      final updated = applyTrueSkill(state: a, opponent: a, score: 0.0);
      expect(updated.mu, lessThan(25.0));
    });

    test('sigma decreases after any match (more data → less uncertainty)', () {
      final a = TrueSkillState.initial();
      final b = TrueSkillState.initial();
      final win = applyTrueSkill(state: a, opponent: b, score: 1.0);
      final loss = applyTrueSkill(state: a, opponent: b, score: 0.0);
      final tie = applyTrueSkill(state: a, opponent: b, score: 0.5);
      expect(win.sigma, lessThan(a.sigma));
      expect(loss.sigma, lessThan(a.sigma));
      expect(tie.sigma, lessThan(a.sigma));
    });

    test('reference: equal players, one wins → mu ≈ 29.21 / 20.79, sigma ≈ 7.19', () {
      // Derived from TrueSkill formulae with sigma=25/3, beta=25/6.
      // c² = 2·sigma² + 2·beta² = 6250/36; c = sqrt(6250)/6 ≈ 13.176
      // t=0, v=phi(0)/Phi(0)≈0.7979, w=v²≈0.6367
      // mu_winner = 25 + sigma²/c·v ≈ 29.21, sigma'≈7.19
      final player = TrueSkillState.initial();
      final updated = applyTrueSkill(state: player, opponent: player, score: 1.0);
      expect(updated.mu, closeTo(29.21, 0.1));
      expect(updated.sigma, closeTo(7.19, 0.1));
    });

    test('tie between equal players leaves mu unchanged (delta < 0.01)', () {
      final a = TrueSkillState.initial();
      final updated = applyTrueSkill(state: a, opponent: a, score: 0.5);
      expect((updated.mu - 25.0).abs(), lessThan(0.01));
    });

    test('assert fires for invalid score (not 0.0, 0.5, or 1.0)', () {
      final a = TrueSkillState.initial();
      expect(
        () => applyTrueSkill(state: a, opponent: a, score: 0.7),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
