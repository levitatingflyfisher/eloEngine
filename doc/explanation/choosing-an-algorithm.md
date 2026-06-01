# Choosing an algorithm

`elo_engine` ships 15 ranking algorithms. They all take the same input
(a list of pairwise match outcomes) and produce the same shape of output
(an ordering of the items), but they disagree — sometimes dramatically —
about how to turn comparisons into a ranking. Picking the right subset
matters both for **speed** and for **correctness on your particular
data**.

This document answers *which algorithms to enable*. For *how each
algorithm works under the hood*, see the files under
[`algorithms/`](algorithms/).

---

## The one-paragraph version

If you do not know what to pick, enable **ELO only** and ship. ELO is
O(1) per match, produces stable rankings within a few dozen
comparisons, and is the most widely-understood algorithm in the
bunch. When you later need a second opinion — or you find yourself
defending your ranking to a skeptical audience — enable the full
ensemble with `compareAlgorithms()` and look at the consensus ranking
and inter-algorithm Kendall tau. Disagreement between algorithms is a
feature: it tells you when the data is genuinely ambiguous.

---

## Three questions that pick the algorithm for you

### Q1: Is this a live, incremental ranking, or an end-of-session analysis?

- **Live (update after every match):** use `EloConfig(enabledAlgorithms: {AlgorithmId.elo})`, or the `{elo, glicko2, trueskill}` trio if you want uncertainty-aware scores. These three algorithms maintain state *inside* `record()`, so they cost essentially nothing per match. The other twelve are **batch** algorithms — they recompute from the full history every time `compareAlgorithms()` is called, so they are wasted work if you call them on every update.

- **Batch (compute once at the end):** any subset is fine. The cost is dominated by `PairwiseMatrix.fromHistory()` and the most expensive algorithms (matrix factorization, SpringRank). The full 15-algorithm run over N=200 items takes ~730 ms on JIT; see the Performance section of the root `README.md` for measured numbers.

### Q2: Do your users produce enough matches for a probabilistic algorithm to stabilize?

- **A few dozen matches, or heavily uneven coverage (some items barely seen):** algorithms that *assume a probabilistic model* — ELO, Glicko-2, TrueSkill, Bradley-Terry, Thurstone — will produce wide error bars. Use them, but show uncertainty in your UI (Glicko-2's RD, TrueSkill's σ). Also enable **Borda** or **Copeland** as a sanity check; they degrade more gracefully on sparse data because they do not need a parameter fit.

- **Hundreds or thousands of matches:** the probabilistic algorithms sing. Glicko-2 and TrueSkill will separate skill from luck better than plain ELO. Bradley-Terry's MLE becomes reliable. Matrix factorization starts to reveal latent dimensions if they exist.

### Q3: Do you trust pairwise comparisons to be consistent, or do you expect preference cycles?

"A beats B, B beats C, and yet C beats A" is not a bug in your data —
it is a real phenomenon (rock-paper-scissors, non-transitive tastes,
heterogeneous voters). It breaks the implicit assumption behind ELO,
Glicko-2, and TrueSkill, which all assume a single underlying skill.

- **You trust transitivity:** ELO family + Bradley-Terry + SpringRank. These all project the data onto a one-dimensional skill axis.

- **You suspect cycles or multi-dimensional preferences:** add **HodgeRank** (directly quantifies the cyclic component), **SerialRank** (measures how well a 1-D ordering fits), and **matrix factorization** (reveals latent dimensions). If `HodgeResult.cyclicMagnitude` is large or `SerialRankResult.rankability` is small, *your data genuinely resists a single ranking*, and you should tell your users that.

- **Vote-theoretic fairness matters more than probabilistic modeling:** use **Schulze**, **Ranked Pairs**, or **Copeland**. These come from social choice theory and pass properties like the Condorcet winner criterion. They are what you want for governance votes, jury rankings, or any situation where "this algorithm is fair" is the argument you will have to defend.

---

## Three useful presets

### Preset: "just rank things"
```dart
EloConfig(enabledAlgorithms: {AlgorithmId.elo})
```
- Cost: O(1) per match, O(N log N) for `rankings`.
- What you lose: uncertainty tracking, cross-algorithm sanity check.
- Use for: Baby Names, wishlist rankers, anything where the user just wants *an* answer.

### Preset: "online trio with uncertainty"
```dart
EloConfig(enabledAlgorithms: {
  AlgorithmId.elo,
  AlgorithmId.glicko2,
  AlgorithmId.trueskill,
})
```
- Cost: ~10 ms for `compareAlgorithms()` at N=200.
- What you gain: Glicko-2's RD and TrueSkill's σ quantify *how sure we are*, so your UI can say "this ranking is locked in" vs "we need more data".
- Use for: leaderboards, skill-rating systems, adaptive matchmaking.

### Preset: "voting theory consensus"
```dart
EloConfig(enabledAlgorithms: {
  AlgorithmId.copeland,
  AlgorithmId.schulze,
  AlgorithmId.rankedPairs,
  AlgorithmId.borda,
})
```
- Cost: ~20 ms at N=200. All four are batch, so call `compareAlgorithms()` at the end, not inside the match loop.
- What you gain: four independent votes using different fairness axioms. When they agree, the ranking is very defensible. When they disagree, you have a non-transitive data set and the choice is a values question.
- Use for: governance, jury rankings, family decisions where "fairness" is the UX claim.

---

## The honest tradeoff table

| Algorithm | Online? | Handles cycles? | Needs many matches? | Dominant cost | Best at |
|---|---|---|---|---|---|
| **ELO** | ✅ | ❌ | ❌ | O(1)/match | Default. Ship this. |
| **Glicko-2** | ✅ | ❌ | ❌ | O(1)/match | Live ratings with uncertainty |
| **TrueSkill** | ✅ | ❌ | ❌ | O(1)/match | Matchmaking, skill-only |
| **Bradley-Terry** | ❌ | ❌ | ✅ | O(N² × iter) | Principled MLE baseline |
| **Thurstone** | ❌ | ❌ | ✅ | O(N² × iter) | Normal-distributed skills |
| **SpringRank** | ❌ | Partially | ✅ | O(N³) | Hierarchies (who-beats-who dominance) |
| **PageRank** | ❌ | ✅ | ❌ | O(N² × iter) | Endorsement networks |
| **Markov** | ❌ | ✅ | ❌ | O(N² × iter) | Random-walk ranking |
| **Copeland** | ❌ | ✅ | ❌ | O(N²) | Simplest Condorcet-ish method |
| **Schulze** | ❌ | ✅ | ❌ | O(N³) | Fair voting, Condorcet-compliant |
| **Ranked Pairs** | ❌ | ✅ | ❌ | O(N² log N) | Alternative fair voting |
| **Borda** | ❌ | ✅ | ❌ | O(N²) | Cheap, intuitive |
| **HodgeRank** | ❌ | ✅ (decomposes) | ❌ | O(N² + edges²) | Detecting cycles |
| **SerialRank** | ❌ | Partially | ❌ | O(N³) | Measuring rankability |
| **MatrixFactorization** | ❌ | ✅ (via latent dims) | ✅ | O(N³ × ranks) | Finding hidden dimensions |

"Online" means the algorithm updates state during `record()` and costs
nothing extra at `compareAlgorithms()` time. Everything else recomputes
from history.

"Handles cycles" means the algorithm produces a sensible output (rather
than numerical garbage) when the pairwise preference graph contains
intransitive loops.

---

## When to enable *everything*

The full 15-algorithm ensemble is genuinely useful when:

- You are **writing a thesis** or publishing a result, and you need to
  say "we compared 15 ranking methods and they agreed/disagreed".
- You are **exploring unknown data** and do not yet know which
  algorithm matches your domain.
- You are **building a demo** that shows off the library (Baby Names'
  "agreement" screen, for example).

For production code that runs on every user session, be selective. The
full ensemble at N=200 is ~730 ms — not expensive in the abstract, but
not free either. Pick the subset that answers the question you are
actually asking.

---

## Further reading

- [`algorithms/elo.md`](algorithms/elo.md) — the default.
- [`algorithms/glicko2.md`](algorithms/glicko2.md) — ELO with
  uncertainty.
- [`algorithms/trueskill.md`](algorithms/trueskill.md) — Microsoft's
  matchmaking system.
- [`algorithms/bradley-terry.md`](algorithms/bradley-terry.md) — the
  statistical foundation under ELO.
- [`algorithms/thurstone.md`](algorithms/thurstone.md) — Bradley-Terry's
  Gaussian cousin.
- [`algorithms/spring-rank.md`](algorithms/spring-rank.md) —
  hierarchies via physics.
- [`algorithms/pagerank.md`](algorithms/pagerank.md) — what Google uses
  for web pages, applied to your match graph.
- [`algorithms/markov.md`](algorithms/markov.md) — stationary
  distributions.
- [`algorithms/copeland.md`](algorithms/copeland.md) — count wins, done.
- [`algorithms/schulze.md`](algorithms/schulze.md) — beatpath winner.
- [`algorithms/ranked-pairs.md`](algorithms/ranked-pairs.md) —
  Tideman's method.
- [`algorithms/borda.md`](algorithms/borda.md) — points for position.
- [`algorithms/hodge.md`](algorithms/hodge.md) — decomposing preference
  flow into grad + curl + harmonic.
- [`algorithms/serial-rank.md`](algorithms/serial-rank.md) — seriation
  as ranking.
- [`algorithms/matrix-factorization.md`](algorithms/matrix-factorization.md)
  — latent dimensions of preference.
