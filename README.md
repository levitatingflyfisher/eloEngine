# elo_engine

A Dart library for pairwise comparison ranking. Give it a list of items,
ask it which pair to compare next, record the outcome, and get a robust
consensus ranking from 15 algorithms.

**Use cases:** baby name pickers, holiday destination rankers, group
preference aggregation, any situation where you want to rank N items by
having people choose between pairs.

Pure Dart, no dependencies, MIT licensed.

---

## Quick start

```dart
import 'package:elo_engine/elo_engine.dart';

final engine = EloEngine(
  items: ['Alpha', 'Beta', 'Gamma'].map((n) => EloItem(id: n)).toList(),
);
final match = engine.nextMatch()!;
engine.record(match.itemA.id, match.itemB.id, MatchOutcome.aWins);
for (final item in engine.rankings) print('${item.id}: ${item.rating}');
```

Run the interactive demo: `dart run example/main.dart`

---

## Documentation

Full documentation lives under [`doc/`](doc/), organised with the
[Diátaxis](https://diataxis.fr/) framework.

**New here?** Start with the [getting-started tutorial](doc/tutorial/getting-started.md).

**Looking up a type or method?** See the
[API reference](doc/reference/api.md).

**Need a recipe?** The [how-to guides](doc/how-to/) cover:

- [Save and restore state](doc/how-to/save-and-restore-state.md)
- [Aggregate group decisions](doc/how-to/aggregate-group-decisions.md)
- [Merge independent rankings](doc/how-to/merge-independent-rankings.md)
  — for when each voter must rank privately.
- [Display per-algorithm rankings](doc/how-to/display-per-algorithm-rankings.md)
- [Pick a subset of algorithms](doc/how-to/pick-algorithm-subset.md) —
  trim the ensemble for speed on phones.
- [Configure convergence](doc/how-to/configure-convergence.md)
- [Undo a match](doc/how-to/undo-a-match.md)

**Curious about the math?** The explanation section covers
[how to choose an algorithm](doc/explanation/choosing-an-algorithm.md) and
a dedicated 3Blue1Brown-style deep-dive for each of the
[15 algorithms](doc/explanation/algorithms/).

**Using this from an LLM coding assistant?** [`AGENTS.md`](AGENTS.md) is a
compact orientation designed to drop into model context.

---

## The 15 algorithms

No single ranking algorithm is universally best. Each makes different
assumptions about the nature of preferences, and those assumptions
interact with the structure of your data (sparse vs dense, transitive vs
cyclic, one voter vs many). `compareAlgorithms()` runs all 15 and
synthesises a consensus. When they agree (`interAlgorithmKendallTau > 0.9`),
you can trust the ranking. When they disagree, the divergence data tells
you which items are genuinely ambiguous and why.

| Algorithm | Key assumption | Strongest when |
|-----------|---------------|----------------|
| ELO | Rating difference predicts win probability via logistic function | Continuous online updates, few items |
| Glicko-2 | Rating has uncertainty (RD) that shrinks with matches; volatility tracks consistency | Mixed activity levels, some items rarely compared |
| TrueSkill | Bayesian Gaussian belief propagation; conservative score = μ − 3σ | Small item sets, uncertain early data |
| Bradley-Terry | Win probability proportional to ratio of latent "strength" parameters | Dense, transitive data |
| Thurstone | Preferences sampled from normal distributions; Case V assumes equal variance | Psychological preference data |
| SpringRank | Items connected by springs; equilibrium positions minimise energy | Hierarchical or competitive data |
| Borda | Score = sum of positions beaten | Many voters, simple aggregation needed |
| Copeland | Score = wins − losses | Condorcet efficiency matters |
| PageRank | Win graph treated like a web graph; authority flows to consistent winners | Cyclic data where chains of wins matter |
| Markov | Stationary distribution of a random walk on the win graph | Indirect comparison chains |
| Schulze | Beat-path: A beats B if the strongest path from A to B beats all paths from B to A | Group voting, Condorcet compliance required |
| Ranked Pairs | Lock in the strongest wins that don't create cycles (Tideman method) | Political-style elections, Condorcet compliance |
| HodgeRank | Hodge decomposition separates gradient (transitive), cyclic, and harmonic flow | Diagnosing non-transitivity |
| SerialRank | Similarity matrix reordering; `rankability` measures how 1-dimensional preferences are | Testing whether preferences are genuinely uni-dimensional |
| Matrix Factorization | Low-rank approximation of the comparison matrix | Latent-factor recovery, multi-dimensional preferences |

For a decision guide across all 15 with presets and honest tradeoffs,
see [doc/explanation/choosing-an-algorithm.md](doc/explanation/choosing-an-algorithm.md).

---

## Performance

Measured with `dart run benchmark/main.dart` on a developer laptop, JIT
(`dart run`), N=200 items, ~1000 recorded matches, seed `rng(42)`.
Numbers are mean latency across multiple iterations. Your hardware will
differ — these are orientation, not promises.

| Operation | N=50 | N=100 | N=200 |
|-----------|------|-------|-------|
| `record()` (single match) | 80 µs | 199 µs | 728 µs |
| `nextMatch()` (pair proposal) | 228 µs | 838 µs | 3.4 ms |
| `compareAlgorithms()` all 15 | 41 ms | 128 ms | **655 ms** |
| `compareAlgorithms()` online-only ¹ | 336 µs | 892 µs | **3.0 ms** |
| `compareAlgorithms()` `{elo, borda}` | 191 µs | 613 µs | **1.8 ms** |

¹ `enabledAlgorithms: {elo, glicko2, trueskill}` — skips the pairwise
matrix entirely.

- **The interactive hot paths are fast.** `record()` and `nextMatch()`
  run in well under 5 ms even at N=200.
- **The full 15-algorithm ensemble is a research mode, not an
  interactive mode.** At N=200 it takes ~0.65 s. Fine for an end-of-
  session analysis button, not for a tight UI loop.
- **`enabledAlgorithms` is the interactive escape hatch.** Restricting
  to online-only or a small batch subset yields a **200–400× speedup**
  at N=200. See
  [pick-algorithm-subset.md](doc/how-to/pick-algorithm-subset.md).

### JIT vs AOT

The benchmark measures JIT (`dart run`) performance. Pure numerical code
with a lot of polymorphic container access (Maps, generic Lists,
iterative solvers over doubles) often runs ~1.5× *slower* under AOT than
JIT in Dart — the JIT's profile-guided type specialization pays off here
more than whole-program AOT compilation does. Flutter release builds are
AOT, so when you run this library inside a Flutter app in release mode,
expect the full-ensemble number to be closer to ~1 s at N=200. The
interactive paths (`record`, `nextMatch`, `compareAlgorithms` with a
subset) stay fast in both modes.

### Regression guards

The benchmark exits with a non-zero status if any of these tripwires
fires:

| Guard | Target | Rationale |
|-------|--------|-----------|
| `nextMatch()` at N=200 | < 5 ms | Interactive proposal must feel instant. |
| `compareAlgorithms()` all-15 at N=200 | < 750 ms | Developer-time upper bound on the research path. |
| `compareAlgorithms()` online-only at N=200 | < 10 ms | Fast subset must stay fast. |
| `compareAlgorithms()` elo+borda at N=200 | < 10 ms | Fast subset must stay fast. |

These aren't promises to consumers — they're tripwires for catching
performance regressions during development. Run `dart run
benchmark/main.dart` before shipping changes that touch `lib/src/`.

---

## License

MIT. Copyright © 2026 OpenHearth contributors. See [LICENSE](LICENSE).
