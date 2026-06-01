# elo_engine documentation

Documentation is organised using the [Diátaxis](https://diataxis.fr/)
framework: four purposes, four locations.

| Folder | Purpose | Start here when |
|--------|---------|-----------------|
| [`tutorial/`](tutorial/) | Learning-oriented walkthroughs | You are new to `elo_engine` and want to rank a list from scratch. |
| [`how-to/`](how-to/) | Goal-oriented recipes | You know what you want to do; you need the snippet. |
| [`reference/`](reference/) | Information-oriented API docs | You are looking up a type, field, or method signature. |
| [`explanation/`](explanation/) | Understanding-oriented background | You want to know why the library does what it does, or how an algorithm works. |

## Tutorials

- [Getting started](tutorial/getting-started.md) — rank a list from
  scratch in 5 steps.

## How-to guides

- [Save and restore state](how-to/save-and-restore-state.md)
- [Aggregate group decisions](how-to/aggregate-group-decisions.md)
- [Merge independent rankings](how-to/merge-independent-rankings.md)
- [Display per-algorithm rankings](how-to/display-per-algorithm-rankings.md)
- [Pick a subset of algorithms](how-to/pick-algorithm-subset.md)
- [Configure convergence](how-to/configure-convergence.md)
- [Undo a match](how-to/undo-a-match.md)

## Reference

- [API reference](reference/api.md) — every public type exported from
  `package:elo_engine/elo_engine.dart`.

## Explanation

- [Choosing an algorithm](explanation/choosing-an-algorithm.md) — a
  decision guide across all 15 algorithms.
- [Algorithm deep-dives](explanation/algorithms/) — one 3Blue1Brown-style
  explanation per algorithm (ELO, Glicko-2, TrueSkill, Bradley-Terry,
  Thurstone, SpringRank, PageRank, Markov, HodgeRank, SerialRank,
  Copeland, Schulze, Ranked Pairs, Borda, Matrix Factorization).
