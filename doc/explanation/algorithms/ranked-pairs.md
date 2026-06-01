# Ranked Pairs (Tideman)

## TL;DR — when to pick it

Enable Ranked Pairs when you want a voting-theory-grade ranking with
**the clearest possible narrative**: "lock in the strongest pairwise
wins first, skip any that would create a cycle with what's already
locked in, and read off the resulting order". Ranked Pairs
(sometimes called Tideman's method) produces almost the same answer
as Schulze but is easier to explain because the algorithm is
literally a greedy sort. Use it when the ranking has to be
defensible to a committee, and when "we processed the matches in
order of margin size" is the explanation you want to give.

## The core idea

Ranked Pairs is one of the cleanest algorithms in the ensemble and
the easiest to run by hand.

1. Compute every pairwise matchup. For pair $(i, j)$ with $w_{ij}$
   wins of $i$ over $j$, record the **majority winner** (whichever
   has more wins) and the **margin size** $|w_{ij} - w_{ji}|$.
2. Sort the list of pairwise matchups by margin size, descending.
3. Walk down the sorted list. For each matchup, **lock it in** (add
   a directed edge from winner to loser in a growing "lock" graph)
   **unless** adding that edge would create a cycle with edges
   already locked in.
4. After walking the full list, do a topological sort of the lock
   graph. That's your ranking.

That's the whole algorithm. Condorcet-compliant, cycle-aware,
margin-sensitive, and fully explainable to a non-technical reader.

## Worked example

Four items: A, B, C, D.

Pairwise matchups with margins:

| Pair | Winner | Margin |
|---|---|---|
| A vs D | A | 10 |
| A vs B | A | 6 |
| B vs C | B | 4 |
| C vs D | C | 3 |
| A vs C | A | 2 |
| B vs D | B | 1 |

Sort by margin, descending: (A>D, 10), (A>B, 6), (B>C, 4), (C>D, 3),
(A>C, 2), (B>D, 1).

Walk the list, locking each unless it creates a cycle:

1. Lock A → D. No cycles possible yet.
2. Lock A → B. No cycles.
3. Lock B → C. No cycles.
4. Lock C → D. Does this create a cycle with existing edges? A → D
   and A → B → C → D… there's no path from D back to C, so no
   cycle. Lock it.
5. Lock A → C. Is there a path from C to A already? A → B → C, so
   no. No cycle. Lock it.
6. Lock B → D. Path from D to B? A → D exists but D has no
   outgoing edges. No cycle. Lock it.

Final lock graph:
```
   A ─→ B
   │    │
   │    ↓
   ↓    C
   D ←──┘
   ↑
   A (already)
```

All edges: A→D, A→B, B→C, C→D, A→C, B→D.

Topological sort: A (no incoming), B (incoming from A only, which
is placed), C (incoming from A and B), D (incoming from A, B, C).

Ranking: A > B > C > D.

## What happens when there's a cycle

Suppose the margins had been different and we encountered a
tie-breaking situation. Consider:

1. Lock A → B (strongest, say margin 5).
2. Lock B → C (next, margin 4).
3. Lock C → A (next, margin 3).

Locking C → A would create a cycle: A → B → C → A. Ranked Pairs
**refuses** to lock this edge. C → A is dropped from the lock
graph.

What we've committed to is: A → B, B → C. The C → A result is
acknowledged (C did beat A) but overridden by the stronger A → B
and B → C. Topological sort: A > B > C.

This is the defining behavior of Ranked Pairs: **bigger margins
win**. The margin-3 cycle-creating edge is sacrificed to preserve
the two larger-margin edges.

Notice that this is margin-sensitive in a way Copeland is not.
Copeland would have scored:
- A beats B, loses to C: Copeland = 0.
- B beats C, loses to A: Copeland = 0.
- C beats A, loses to B: Copeland = 0.

All tied. Ranked Pairs uses the sizes to break the cycle.

## Why it's so explainable

The three-step story — "sort by margin, lock in order, skip cycles"
— is intuitive even to someone who has never heard of voting theory.
Contrast with:

- **Schulze**: "find the widest chain of pairwise wins from each
  item to each other" — requires explaining beatpaths and
  Floyd-Warshall.
- **Borda**: "sum up position points" — simple but fails some
  fairness axioms.
- **ELO**: "run these logistic updates one match at a time" —
  requires explaining probability models.

Ranked Pairs sits in the sweet spot: smart enough to be
Condorcet-compliant, simple enough to run in your head for small
examples.

## Axiomatic properties

Ranked Pairs satisfies:

- **Condorcet winner criterion.** The Condorcet winner has the
  strongest margin in every pairwise matchup, so Ranked Pairs
  locks in all its wins first and it ends up top of the
  topological sort.
- **Condorcet loser criterion.** A Condorcet loser loses every
  head-to-head, so its edges only get locked in when nothing else
  contradicts them — ending up at the bottom.
- **Monotonicity.** Improving an item can only raise its rank.
- **Independence of clones** (usually; there are pathological
  counterexamples in the literature).

It fails one property that Schulze passes: consistency across
certain "uniform ballot perturbations". This is a rare edge case
that does not matter for practical rankings.

## Comparison to Schulze

Schulze and Ranked Pairs usually agree. When they don't:

- **Ranked Pairs** tends to be sharper on data with clear margin
  hierarchies.
- **Schulze** is smoother and slightly more robust to small
  margin differences at the top.

If your data is well-separated (big margins for the top items,
smaller margins at the bottom), both give the same answer. If your
data is a jumble of small margins, they can differ. Enable both in
the ensemble and use the disagreement as a signal.

## Failure modes

**Tied margins.** If two pairwise matches have exactly the same
margin, the tie-break order matters. `elo_engine` uses a
deterministic tiebreaker (input order) so results are reproducible,
but a different tiebreaker could give a different ranking. In
practice this only affects low-information situations.

**Sparse data.** Margins are computed over observed matches only.
Pairs with zero matches contribute nothing to the sort and are
effectively ignored. The resulting lock graph may be sparse and
produce a partial ranking (ties in the topological sort). `elo_
engine` resolves these by falling back to input order.

**Cyclic majority with equal margins.** If A > B, B > C, C > A,
and all three margins are equal, Ranked Pairs has to break the tie
arbitrarily. The resulting ranking depends on iteration order and
is not uniquely determined by the data.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when `AlgorithmId.rankedPairs`
  is enabled.
- Exposed as `RankingComparison.rankedPairsRanking`.
- Uses margin-sorted greedy locking with cycle detection via DFS.
  Cost is $O(N^2 \log N)$ for the sort plus $O(N^2)$ for the lock
  sweep.

## One-sentence summary

Ranked Pairs is "sort pairwise wins by margin size, lock each
winner-over-loser result in order, skip anything that would
create a cycle, topologically sort the survivors" — the most
easily-explained Condorcet-compliant method in the ensemble.
